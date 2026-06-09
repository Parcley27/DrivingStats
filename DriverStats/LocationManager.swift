//
//  LocationManager.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import CoreLocation
import Combine
import Foundation

struct RoutePoint {
    let coordinate: CLLocationCoordinate2D
    let speedMps: Double
    let altitudeM: Double
}

@MainActor
class LocationManager: NSObject, ObservableObject {

    private let manager = CLLocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var trackPoints: [RoutePoint] = []
    /// m/s, negative means no valid fix
    @Published private(set) var speed: Double = -1
    /// Degrees clockwise from true north, negative means no valid fix
    @Published private(set) var course: Double = -1
    /// Meters, negative means no valid fix
    @Published private(set) var horizontalAccuracy: Double = -1
    @Published private(set) var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    @Published private(set) var altitudeM: Double = 0
    @Published private(set) var lastUpdate: Date?

    /// Minimum speed (m/s) below which GPS course is considered unreliable
    static let minReliableSpeedMps: Double = 2.0
    /// Maximum horizontal accuracy (m) above which the fix is considered too poor to use
    static let maxReliableAccuracyM: Double = 50.0

    /// True when location is authorized and the horizontal accuracy is good enough to use
    var hasValidFix: Bool {
        (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways) &&
        horizontalAccuracy >= 0 &&
        horizontalAccuracy < Self.maxReliableAccuracyM
    }

    var isCourseReliable: Bool {
        course >= 0 &&
        speed >= Self.minReliableSpeedMps &&
        horizontalAccuracy >= 0 &&
        horizontalAccuracy < Self.maxReliableAccuracyM
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
    }

    func startTrack() {
        trackPoints = []
    }

    func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            // Request "Always" so GPS and CoreMotion continue with the screen off.
            // Requires NSLocationAlwaysAndWhenInUseUsageDescription in Info.plist
            // and "Location updates" under target Signing & Capabilities > Background Modes.
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates()
        default:
            break
        }
    }

    private func startLocationUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.speed = loc.speed
            self?.course = loc.course
            self?.horizontalAccuracy = loc.horizontalAccuracy
            self?.coordinate = loc.coordinate
            self?.altitudeM = loc.altitude
            self?.lastUpdate = Date()
            if loc.horizontalAccuracy >= 0 {
                self?.trackPoints.append(RoutePoint(
                    coordinate: loc.coordinate,
                    speedMps: max(0, loc.speed),
                    altitudeM: loc.altitude
                ))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                self.startLocationUpdates()
            }
        }
    }
}
