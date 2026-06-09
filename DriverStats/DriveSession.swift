//
//  DriveSession.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import CoreLocation
import Foundation
import SwiftData

extension Int {
    var formattedBytes: String {
        if self < 1_024 { return "\(self) B" }
        if self < 1_024 * 1_024 { return String(format: "%.1f KB", Double(self) / 1_024) }
        return String(format: "%.1f MB", Double(self) / (1_024 * 1_024))
    }
}

@Model
final class DriveSession {

    // MARK: Time
    var startDate: Date = Date()
    var durationSeconds: Double = 0
    var stoppingTimeSeconds: Double = 0
    var stopCount: Int = 0

    // MARK: Distance
    var totalDistanceM: Double = 0

    // MARK: Speed
    var maxSpeedMps: Double = 0
    var avgSpeedMps: Double = 0
    var avgMovingSpeedMps: Double = 0

    // MARK: Longitudinal
    var peakForward: Double = 0
    var peakBraking: Double = 0
    var avgLongitudinalAbs: Double = 0
    var rmsForward: Double = 0
    var hardAccelCount: Int = 0
    var hardBrakingCount: Int = 0
    var peakJerkForward: Double = 0
    var peakJerkBraking: Double = 0
    var avgJerkLongitudinalAbs: Double = 0

    // MARK: Lateral
    var peakRight: Double = 0
    var peakLeft: Double = 0
    var avgLateralAbs: Double = 0
    var rmsLateral: Double = 0
    var hardCorneringCount: Int = 0
    var peakJerkRight: Double = 0
    var peakJerkLeft: Double = 0
    var avgJerkLateralAbs: Double = 0

    // MARK: Vertical
    var peakUp: Double = 0
    var peakDown: Double = 0
    var avgVerticalAbs: Double = 0
    var rmsVertical: Double = 0
    var peakJerkUp: Double = 0
    var peakJerkDown: Double = 0
    var avgJerkVerticalAbs: Double = 0

    // MARK: Net
    var peakNetAccel: Double = 0
    var avgNetAccel: Double = 0
    var rmsNet: Double = 0
    var peakNetJerk: Double = 0
    var avgNetJerk: Double = 0

    // MARK: Surface events
    var surfaceEventCount: Int = 0

    // MARK: Route (parallel arrays)
    var routeLatitudes: [Double] = []
    var routeLongitudes: [Double] = []
    var routeSpeeds: [Double] = []
    var routeAltitudes: [Double] = []

    // MARK: Peak event annotations (parallel arrays — type raw value, lat, lon, formatted string)
    var peakEventTypes: [Int] = []
    var peakEventLats: [Double] = []
    var peakEventLons: [Double] = []
    var peakEventFormatted: [String] = []

    init(result: SessionResult) {
        let s = result.stats
        startDate = s.startDate
        durationSeconds = s.durationSeconds
        stoppingTimeSeconds = s.stoppingTimeSeconds
        stopCount = s.stopCount
        totalDistanceM = s.totalDistanceM
        maxSpeedMps = s.maxSpeedMps
        avgSpeedMps = s.avgSpeedMps
        avgMovingSpeedMps = s.avgMovingSpeedMps
        peakForward = s.peakForward
        peakBraking = s.peakBraking
        avgLongitudinalAbs = s.avgLongitudinalAbs
        rmsForward = s.rmsForward
        hardAccelCount = s.hardAccelCount
        hardBrakingCount = s.hardBrakingCount
        peakJerkForward = s.peakJerkForward
        peakJerkBraking = s.peakJerkBraking
        avgJerkLongitudinalAbs = s.avgJerkLongitudinalAbs
        peakRight = s.peakRight
        peakLeft = s.peakLeft
        avgLateralAbs = s.avgLateralAbs
        rmsLateral = s.rmsLateral
        hardCorneringCount = s.hardCorneringCount
        peakJerkRight = s.peakJerkRight
        peakJerkLeft = s.peakJerkLeft
        avgJerkLateralAbs = s.avgJerkLateralAbs
        peakUp = s.peakUp
        peakDown = s.peakDown
        avgVerticalAbs = s.avgVerticalAbs
        rmsVertical = s.rmsVertical
        peakJerkUp = s.peakJerkUp
        peakJerkDown = s.peakJerkDown
        avgJerkVerticalAbs = s.avgJerkVerticalAbs
        peakNetAccel = s.peakNetAccel
        avgNetAccel = s.avgNetAccel
        rmsNet = s.rmsNet
        peakNetJerk = s.peakNetJerk
        avgNetJerk = s.avgNetJerk
        surfaceEventCount = s.surfaceEventCount
        routeLatitudes = result.track.map(\.coordinate.latitude)
        routeLongitudes = result.track.map(\.coordinate.longitude)
        routeSpeeds = result.track.map(\.speedMps)
        routeAltitudes = result.track.map(\.altitudeM)
        peakEventTypes = result.peakEvents.map { $0.type.rawValue }
        peakEventLats = result.peakEvents.map { $0.coordinate.latitude }
        peakEventLons = result.peakEvents.map { $0.coordinate.longitude }
        peakEventFormatted = result.peakEvents.map { $0.formatted }
    }

    // MARK: Computed helpers

    var movingTimeSeconds: Double { max(0, durationSeconds - stoppingTimeSeconds) }

    /// Approximate in-database size
    var estimatedSizeBytes: Int { (routeLatitudes.count * 4 + peakEventTypes.count * 4) * 8 + 380 }

    var routePoints: [RoutePoint] {
        let hasAlt = routeAltitudes.count == routeLatitudes.count
        let alts = hasAlt ? routeAltitudes : Array(repeating: 0.0, count: routeLatitudes.count)
        return zip(zip(routeLatitudes, routeLongitudes), zip(routeSpeeds, alts)).map { coords, sa in
            RoutePoint(
                coordinate: CLLocationCoordinate2D(latitude: coords.0, longitude: coords.1),
                speedMps: sa.0,
                altitudeM: sa.1
            )
        }
    }

    var speedsKph: [Double] { routeSpeeds.map { $0 * 3.6 } }

    var altitudesM: [Double] { routeAltitudes }

    var peakEventsRestored: [PeakEvent] {
        zip(zip(peakEventTypes, zip(peakEventLats, peakEventLons)), peakEventFormatted)
            .compactMap { typeCoord, formatted in
                let (typeInt, (lat, lon)) = typeCoord
                guard let type = PeakEventType(rawValue: typeInt) else { return nil }
                return PeakEvent(
                    type: type,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    formatted: formatted
                )
            }
    }
}
