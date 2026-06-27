//
//  SessionStats.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Foundation

/// Accumulates peak and average statistics for a tracking session.
/// All acceleration values are in g. Speed values are in m/s.
struct SessionStats {

    // MARK: Time
    var startDate: Date = Date()
    private(set) var endDate: Date? = nil
    var durationSeconds: Double { (endDate ?? Date()).timeIntervalSince(startDate) }
    var stoppingTimeSeconds: Double = 0
    var movingTimeSeconds: Double { max(0, durationSeconds - stoppingTimeSeconds) }
    var stopCount: Int = 0
    private var lastSpeedTimestamp: Date? = nil
    private var prevWasMoving: Bool = false
    static let stopThresholdMps: Double = 0.5

    // MARK: Distance
    var totalDistanceM: Double = 0

    // MARK: Speed (GPS)
    var maxSpeedMps: Double = 0
    var avgSpeedMps: Double = 0
    private var totalSpeedMps: Double = 0
    private var speedCount: Int = 0
    var avgMovingSpeedMps: Double = 0
    private var totalMovingSpeedMps: Double = 0
    private var movingSpeedCount: Int = 0

    // MARK: Longitudinal (forward/braking)
    var peakForward: Double = 0
    var peakBraking: Double = 0
    var avgLongitudinalAbs: Double = 0
    private var totalLongitudinalAbs: Double = 0

    // MARK: Lateral (left/right)
    var peakRight: Double = 0
    var peakLeft: Double = 0
    var avgLateralAbs: Double = 0
    private var totalLateralAbs: Double = 0

    // MARK: Vertical — uses effectiveVertical so bumps can be suppressed
    var peakUp: Double = 0
    var peakDown: Double = 0
    var avgVerticalAbs: Double = 0
    private var totalVerticalAbs: Double = 0

    // MARK: Net acceleration magnitude
    var peakNetAccel: Double = 0
    var avgNetAccel: Double = 0
    private var totalNetAccel: Double = 0

    var accelCount: Int = 0

    // MARK: RMS acceleration
    var rmsForward: Double = 0
    var rmsLateral: Double = 0
    var rmsVertical: Double = 0
    var rmsNet: Double = 0
    private var sumSqForward: Double = 0
    private var sumSqLateral: Double = 0
    private var sumSqVertical: Double = 0
    private var sumSqNet: Double = 0

    // MARK: Hard events (configurable threshold, default 0.3 g)
    var hardThresholdG: Double = 0.3
    var hardAccelCount: Int = 0
    var hardBrakingCount: Int = 0
    var hardCorneringCount: Int = 0
    private var isInHardAccel: Bool = false
    private var isInHardBraking: Bool = false
    private var isInHardCornering: Bool = false

    // MARK: Surface events (configurable threshold, default 0.4 g)
    var surfaceEventThresholdG: Double = 0.4
    var surfaceEventCount: Int = 0
    private var isInSurfaceEvent: Bool = false

    // MARK: Jerk (rate of change of acceleration, g/s)
    var peakJerkForward: Double = 0
    var peakJerkBraking: Double = 0
    var avgJerkLongitudinalAbs: Double = 0
    private var totalJerkLongitudinalAbs: Double = 0

    var peakJerkRight: Double = 0
    var peakJerkLeft: Double = 0
    var avgJerkLateralAbs: Double = 0
    private var totalJerkLateralAbs: Double = 0

    var peakJerkUp: Double = 0
    var peakJerkDown: Double = 0
    var avgJerkVerticalAbs: Double = 0
    private var totalJerkVerticalAbs: Double = 0

    var peakNetJerk: Double = 0
    var avgNetJerk: Double = 0
    private var totalNetJerk: Double = 0

    var jerkCount: Int = 0

    // MARK: - Mutations

    mutating func end() {
        endDate = Date()
    }

    /// - Parameters:
    ///   - rawVertical: unsmoothed vertical for surface-event detection
    ///   - effectiveVertical: vertical used for stats (0 when vertical suppression is on)
    mutating func recordAcceleration(forward: Double, lateral: Double,
                                     rawVertical: Double, effectiveVertical: Double) {
        peakForward = max(peakForward, forward)
        peakBraking = min(peakBraking, forward)
        totalLongitudinalAbs += abs(forward)

        peakRight = max(peakRight, lateral)
        peakLeft = min(peakLeft, lateral)
        totalLateralAbs += abs(lateral)

        peakUp   = max(peakUp,   effectiveVertical)
        peakDown = min(peakDown, effectiveVertical)
        totalVerticalAbs += abs(effectiveVertical)

        let net = (forward*forward + lateral*lateral + effectiveVertical*effectiveVertical).squareRoot()
        peakNetAccel = max(peakNetAccel, net)
        totalNetAccel += net

        accelCount += 1
        let n = Double(accelCount)
        avgLongitudinalAbs = totalLongitudinalAbs / n
        avgLateralAbs      = totalLateralAbs / n
        avgVerticalAbs     = totalVerticalAbs / n
        avgNetAccel        = totalNetAccel / n

        sumSqForward  += forward * forward
        sumSqLateral  += lateral * lateral
        sumSqVertical += effectiveVertical * effectiveVertical
        sumSqNet      += net * net
        rmsForward  = (sumSqForward  / n).squareRoot()
        rmsLateral  = (sumSqLateral  / n).squareRoot()
        rmsVertical = (sumSqVertical / n).squareRoot()
        rmsNet      = (sumSqNet      / n).squareRoot()

        let nowHardAccel = forward > hardThresholdG
        if nowHardAccel && !isInHardAccel { hardAccelCount += 1 }
        isInHardAccel = nowHardAccel

        let nowHardBraking = forward < -hardThresholdG
        if nowHardBraking && !isInHardBraking { hardBrakingCount += 1 }
        isInHardBraking = nowHardBraking

        let nowHardCornering = abs(lateral) > hardThresholdG
        if nowHardCornering && !isInHardCornering { hardCorneringCount += 1 }
        isInHardCornering = nowHardCornering

        // Surface events use raw vertical so they are detected regardless of suppression toggle
        let nowSurface = abs(rawVertical) > surfaceEventThresholdG
        if nowSurface && !isInSurfaceEvent { surfaceEventCount += 1 }
        isInSurfaceEvent = nowSurface
    }

    mutating func recordSpeed(_ speedMps: Double) {
        guard speedMps >= 0 else { return }

        maxSpeedMps = max(maxSpeedMps, speedMps)
        totalSpeedMps += speedMps
        speedCount += 1
        avgSpeedMps = totalSpeedMps / Double(speedCount)

        let now = Date()
        let moving = speedMps >= Self.stopThresholdMps

        if let last = lastSpeedTimestamp {
            let dt = now.timeIntervalSince(last)
            if !moving { stoppingTimeSeconds += dt }
            totalDistanceM += speedMps * dt
            if !moving && prevWasMoving { stopCount += 1 }
        }

        if moving {
            totalMovingSpeedMps += speedMps
            movingSpeedCount += 1
            avgMovingSpeedMps = totalMovingSpeedMps / Double(movingSpeedCount)
        }

        prevWasMoving = moving
        lastSpeedTimestamp = now
    }

    mutating func recordJerk(forward: Double, lateral: Double, vertical: Double) {
        peakJerkForward = max(peakJerkForward, forward)
        peakJerkBraking = min(peakJerkBraking, forward)
        totalJerkLongitudinalAbs += abs(forward)

        peakJerkRight = max(peakJerkRight, lateral)
        peakJerkLeft  = min(peakJerkLeft, lateral)
        totalJerkLateralAbs += abs(lateral)

        peakJerkUp   = max(peakJerkUp, vertical)
        peakJerkDown = min(peakJerkDown, vertical)
        totalJerkVerticalAbs += abs(vertical)

        let net = (forward*forward + lateral*lateral + vertical*vertical).squareRoot()
        peakNetJerk = max(peakNetJerk, net)
        totalNetJerk += net

        jerkCount += 1
        let n = Double(jerkCount)
        avgJerkLongitudinalAbs = totalJerkLongitudinalAbs / n
        avgJerkLateralAbs      = totalJerkLateralAbs / n
        avgJerkVerticalAbs     = totalJerkVerticalAbs / n
        avgNetJerk             = totalNetJerk / n
    }
}

// MARK: - Heading orientation correction support

extension SessionStats {
    /// Overwrites all acceleration-derived fields with values from a freshly recomputed stats object.
    /// GPS/speed/distance/stop fields are left untouched.
    mutating func mergeAccelerationResult(_ other: SessionStats) {
        peakForward            = other.peakForward
        peakBraking            = other.peakBraking
        avgLongitudinalAbs     = other.avgLongitudinalAbs
        rmsForward             = other.rmsForward
        hardAccelCount         = other.hardAccelCount
        hardBrakingCount       = other.hardBrakingCount
        peakJerkForward        = other.peakJerkForward
        peakJerkBraking        = other.peakJerkBraking
        avgJerkLongitudinalAbs = other.avgJerkLongitudinalAbs

        peakRight              = other.peakRight
        peakLeft               = other.peakLeft
        avgLateralAbs          = other.avgLateralAbs
        rmsLateral             = other.rmsLateral
        hardCorneringCount     = other.hardCorneringCount
        peakJerkRight          = other.peakJerkRight
        peakJerkLeft           = other.peakJerkLeft
        avgJerkLateralAbs      = other.avgJerkLateralAbs

        peakUp                 = other.peakUp
        peakDown               = other.peakDown
        avgVerticalAbs         = other.avgVerticalAbs
        rmsVertical            = other.rmsVertical
        peakJerkUp             = other.peakJerkUp
        peakJerkDown           = other.peakJerkDown
        avgJerkVerticalAbs     = other.avgJerkVerticalAbs

        peakNetAccel           = other.peakNetAccel
        avgNetAccel            = other.avgNetAccel
        rmsNet                 = other.rmsNet
        peakNetJerk            = other.peakNetJerk
        avgNetJerk             = other.avgNetJerk

        surfaceEventCount      = other.surfaceEventCount
        accelCount             = other.accelCount
        jerkCount              = other.jerkCount
    }
}

// MARK: - Restore from persistent storage

extension SessionStats {
    /// Reconstruct a display-only SessionStats from a stored DriveSession.
    /// Private accumulators stay at zero — safe because no further recording occurs.
    init(restoringFrom session: DriveSession) {
        startDate = session.startDate
        endDate = session.startDate.addingTimeInterval(session.durationSeconds)
        stoppingTimeSeconds = session.stoppingTimeSeconds
        stopCount = session.stopCount
        totalDistanceM = session.totalDistanceM
        maxSpeedMps = session.maxSpeedMps
        avgSpeedMps = session.avgSpeedMps
        avgMovingSpeedMps = session.avgMovingSpeedMps
        peakForward = session.peakForward
        peakBraking = session.peakBraking
        avgLongitudinalAbs = session.avgLongitudinalAbs
        rmsForward = session.rmsForward
        hardAccelCount = session.hardAccelCount
        hardBrakingCount = session.hardBrakingCount
        peakJerkForward = session.peakJerkForward
        peakJerkBraking = session.peakJerkBraking
        avgJerkLongitudinalAbs = session.avgJerkLongitudinalAbs
        peakRight = session.peakRight
        peakLeft = session.peakLeft
        avgLateralAbs = session.avgLateralAbs
        rmsLateral = session.rmsLateral
        hardCorneringCount = session.hardCorneringCount
        peakJerkRight = session.peakJerkRight
        peakJerkLeft = session.peakJerkLeft
        avgJerkLateralAbs = session.avgJerkLateralAbs
        peakUp = session.peakUp
        peakDown = session.peakDown
        avgVerticalAbs = session.avgVerticalAbs
        rmsVertical = session.rmsVertical
        peakJerkUp = session.peakJerkUp
        peakJerkDown = session.peakJerkDown
        avgJerkVerticalAbs = session.avgJerkVerticalAbs
        peakNetAccel = session.peakNetAccel
        avgNetAccel = session.avgNetAccel
        rmsNet = session.rmsNet
        peakNetJerk = session.peakNetJerk
        avgNetJerk = session.avgNetJerk
        surfaceEventCount = session.surfaceEventCount
    }
}
