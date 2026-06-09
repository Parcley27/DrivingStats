//
//  MotionManager.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Combine
import CoreLocation
import CoreMotion
import Foundation

@MainActor
class MotionManager: ObservableObject {

    enum HeadingStatus {
        case noFix
        case gpsFix(course: Double, speedMps: Double, accuracyM: Double)
        case propagated(baseCourse: Double, currentCourse: Double, ageSeconds: Double)
    }

    private struct GPSFix {
        let worldForward: SIMD3<Double>
        let rotMatrix: CMRotationMatrix
        let course: Double
        let speedMps: Double
        let accuracyM: Double
        let timestamp: Date
    }

    private let motion = CMMotionManager()
    private let updateQueue = OperationQueue()

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var currentAcceleration: AccelerationComponents?
    /// Slow-refresh copy of currentAcceleration for display (~2 Hz)
    @Published private(set) var displayAcceleration: AccelerationComponents?
    @Published private(set) var headingStatus: HeadingStatus = .noFix
    @Published private(set) var currentGravity: CMAcceleration?
    @Published private(set) var isStable: Bool = false
    @Published private(set) var recentSamples: [AccelerationSample] = []
    @Published private(set) var sessionStats: SessionStats?
    @Published private(set) var isSessionActive: Bool = false

    /// When true, vertical component is zeroed in stats so road surface events
    /// don't contaminate longitudinal/lateral/net stats. Surface events are still counted.
    @Published var suppressVerticalEvents: Bool = true

    /// Peak events recorded during the session, available after endSession()
    private(set) var peakEvents: [PeakEvent] = []

    private var pendingGPS: (course: Double, speedMps: Double, accuracyM: Double)?
    private var lastFix: GPSFix?
    private var currentCoordinate: CLLocationCoordinate2D?

    // Stability tracking
    private var recentMagnitudes: [Double] = []
    private let stabilityWindow = 25
    private let stabilityThreshold = 0.04

    // Smoothing: 5-sample moving average reduces sensor noise before jerk/stats
    private var accelSmoothing: [SIMD3<Double>] = []
    private let smoothingN = 5

    // Peak coordinate tracking keyed by event type
    private var peakTracker: [PeakEventType: (coord: CLLocationCoordinate2D, value: Double)] = [:]

    // Graph + stats buffer timing
    private var motionTick = 0
    private let graphDownsample = 5
    private var displayTick = 0
    private let displayDownsample = 25
    private let graphBufferSize = 300
    private var graphSampleID = 0
    private var recordingStart: Date?

    private var liveStats = SessionStats()
    private var prevEffective: SIMD3<Double>?
    private var prevTimestamp: Date?

    init() {
        isAvailable = motion.isDeviceMotionAvailable
        startMotionUpdates()
    }

    // MARK: - Session management

    func startSession() {
        liveStats = SessionStats()
        sessionStats = SessionStats()
        isSessionActive = true
        accelSmoothing = []
        peakTracker = [:]
        peakEvents = []
        prevEffective = nil
        prevTimestamp = nil
    }

    func endSession() {
        liveStats.end()
        sessionStats = liveStats
        isSessionActive = false
        buildPeakEvents()
    }

    private func buildPeakEvents() {
        peakEvents = peakTracker.map { type, data in
            let formatted: String
            switch type {
            case .maxSpeed:    formatted = String(format: "%.0f km/h", data.value * 3.6)
            case .peakAccel:   formatted = String(format: "+%.2f g", data.value)
            case .peakBraking: formatted = String(format: "%.2f g", data.value)
            case .peakRight:   formatted = String(format: "+%.2f g", data.value)
            case .peakLeft:    formatted = String(format: "%.2f g", data.value)
            }
            return PeakEvent(type: type, coordinate: data.coord, formatted: formatted)
        }
    }

    // MARK: - GPS input

    var hasValidHeading: Bool {
        if case .noFix = headingStatus { return false }
        return true
    }

    func updateFromGPS(course: Double, speedMps: Double, accuracyM: Double,
                       coordinate: CLLocationCoordinate2D) {
        currentCoordinate = coordinate

        if isSessionActive {
            let prePeak = liveStats.maxSpeedMps
            liveStats.recordSpeed(speedMps)
            if liveStats.maxSpeedMps > prePeak {
                peakTracker[.maxSpeed] = (coordinate, liveStats.maxSpeedMps)
            }
        }

        guard course >= 0,
              speedMps >= LocationManager.minReliableSpeedMps,
              accuracyM >= 0,
              accuracyM < LocationManager.maxReliableAccuracyM
        else { return }
        pendingGPS = (course: course, speedMps: speedMps, accuracyM: accuracyM)
    }

#if DEBUG
    func injectSpoofGPS(course: Double) {
        pendingGPS = (course: course, speedMps: 10.0, accuracyM: 5.0)
    }
#endif

    // MARK: - Motion processing

    private func startMotionUpdates() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: updateQueue) { [weak self] data, error in
            guard let data, error == nil else { return }
            Task { @MainActor [weak self] in
                self?.processMotionData(data)
            }
        }
    }

    private func processMotionData(_ data: CMDeviceMotion) {
        let R_now = data.attitude.rotationMatrix
        currentGravity = data.gravity

        let ua = data.userAcceleration
        let mag = (ua.x*ua.x + ua.y*ua.y + ua.z*ua.z).squareRoot()
        recentMagnitudes.append(mag)
        if recentMagnitudes.count > stabilityWindow { recentMagnitudes.removeFirst() }
        let stable = recentMagnitudes.count == stabilityWindow &&
                     (recentMagnitudes.max() ?? 1.0) < stabilityThreshold
        if isStable != stable { isStable = stable }

        if let pending = pendingGPS {
            let courseRad = pending.course * .pi / 180.0
            let forwardNEU = SIMD3<Double>(cos(courseRad), sin(courseRad), 0)
            lastFix = GPSFix(
                worldForward: forwardNEU,
                rotMatrix: R_now,
                course: pending.course,
                speedMps: pending.speedMps,
                accuracyM: pending.accuracyM,
                timestamp: Date()
            )
            pendingGPS = nil
        }

        guard let fix = lastFix else {
            headingStatus = .noFix
            currentAcceleration = nil
            displayAcceleration = nil
            return
        }

        let R_delta = multiplyR(R_now, byTransposeOf: fix.rotMatrix)
        let forwardNEU = vecNormalize(rotateVec(fix.worldForward, by: R_delta))

        let accelDevice = SIMD3<Double>(ua.x, ua.y, ua.z)
        let accelWorld = rotateVec(accelDevice, by: R_now)

        let up = SIMD3<Double>(0, 0, 1)
        let right = vecNormalize(vecCross(up, forwardNEU))

        let fixAge = Date().timeIntervalSince(fix.timestamp)
        if fixAge < 1.5 {
            headingStatus = .gpsFix(course: fix.course, speedMps: fix.speedMps, accuracyM: fix.accuracyM)
        } else {
            let propagatedCourse = courseDegrees(from: forwardNEU)
            headingStatus = .propagated(baseCourse: fix.course, currentCourse: propagatedCourse, ageSeconds: fixAge)
        }

        // 5-sample moving average to reduce high-frequency sensor noise
        let rawVec = SIMD3<Double>(
            vecDot(accelWorld, forwardNEU),
            vecDot(accelWorld, right),
            vecDot(accelWorld, up)
        )
        accelSmoothing.append(rawVec)
        if accelSmoothing.count > smoothingN { accelSmoothing.removeFirst() }
        let sv = accelSmoothing.reduce(SIMD3<Double>.zero, +) / Double(accelSmoothing.count)

        let rawVertical = rawVec.z
        let effectiveZ = suppressVerticalEvents ? 0.0 : sv.z

        let now = Date()
        let components = AccelerationComponents(forward: sv.x, lateral: sv.y, vertical: sv.z, timestamp: now)
        currentAcceleration = components

        if isSessionActive {
            let preForward = liveStats.peakForward
            let preBraking = liveStats.peakBraking
            let preRight   = liveStats.peakRight
            let preLeft    = liveStats.peakLeft

            liveStats.recordAcceleration(
                forward: sv.x, lateral: sv.y,
                rawVertical: rawVertical, effectiveVertical: effectiveZ
            )

            if let coord = currentCoordinate {
                if liveStats.peakForward > preForward { peakTracker[.peakAccel]   = (coord, liveStats.peakForward) }
                if liveStats.peakBraking < preBraking { peakTracker[.peakBraking] = (coord, liveStats.peakBraking) }
                if liveStats.peakRight   > preRight   { peakTracker[.peakRight]   = (coord, liveStats.peakRight) }
                if liveStats.peakLeft    < preLeft    { peakTracker[.peakLeft]    = (coord, liveStats.peakLeft) }
            }

            if let prev = prevEffective, let prevT = prevTimestamp {
                let dt = now.timeIntervalSince(prevT)
                if dt > 0 {
                    liveStats.recordJerk(
                        forward:  (sv.x    - prev.x) / dt,
                        lateral:  (sv.y    - prev.y) / dt,
                        vertical: (effectiveZ - prev.z) / dt
                    )
                }
            }
        }

        prevEffective = SIMD3<Double>(sv.x, sv.y, effectiveZ)
        prevTimestamp = now

        displayTick += 1
        if displayTick % displayDownsample == 0 {
            displayAcceleration = components
        }

        motionTick += 1
        if motionTick % graphDownsample == 0 {
            if recordingStart == nil { recordingStart = Date() }
            let elapsed = Date().timeIntervalSince(recordingStart!)
            recentSamples.append(AccelerationSample(
                id: graphSampleID,
                elapsedSeconds: elapsed,
                forward: sv.x, lateral: sv.y, vertical: sv.z
            ))
            graphSampleID += 1
            if recentSamples.count > graphBufferSize { recentSamples.removeFirst() }
            if isSessionActive { sessionStats = liveStats }
        }
    }

    // MARK: - Math helpers

    private func courseDegrees(from v: SIMD3<Double>) -> Double {
        var deg = atan2(v.y, v.x) * 180.0 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    private func multiplyR(_ a: CMRotationMatrix, byTransposeOf b: CMRotationMatrix) -> CMRotationMatrix {
        CMRotationMatrix(
            m11: a.m11*b.m11 + a.m12*b.m12 + a.m13*b.m13,
            m12: a.m11*b.m21 + a.m12*b.m22 + a.m13*b.m23,
            m13: a.m11*b.m31 + a.m12*b.m32 + a.m13*b.m33,
            m21: a.m21*b.m11 + a.m22*b.m12 + a.m23*b.m13,
            m22: a.m21*b.m21 + a.m22*b.m22 + a.m23*b.m23,
            m23: a.m21*b.m31 + a.m22*b.m32 + a.m23*b.m33,
            m31: a.m31*b.m11 + a.m32*b.m12 + a.m33*b.m13,
            m32: a.m31*b.m21 + a.m32*b.m22 + a.m33*b.m23,
            m33: a.m31*b.m31 + a.m32*b.m32 + a.m33*b.m33
        )
    }

    private func rotateVec(_ v: SIMD3<Double>, by r: CMRotationMatrix) -> SIMD3<Double> {
        SIMD3(
            r.m11*v.x + r.m12*v.y + r.m13*v.z,
            r.m21*v.x + r.m22*v.y + r.m23*v.z,
            r.m31*v.x + r.m32*v.y + r.m33*v.z
        )
    }

    private func vecDot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x*b.x + a.y*b.y + a.z*b.z
    }

    private func vecCross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
    }

    private func vecNormalize(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let len = (v.x*v.x + v.y*v.y + v.z*v.z).squareRoot()
        guard len > 1e-10 else { return SIMD3(0, 1, 0) }
        return SIMD3(v.x/len, v.y/len, v.z/len)
    }
}
