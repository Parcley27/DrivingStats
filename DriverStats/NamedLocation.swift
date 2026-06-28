//
//  NamedLocation.swift
//  DriverStats
//
//  Created by Pierce Oxley on 6/27/26.
//

import CoreLocation
import Foundation
import SwiftData

@Model
final class NamedLocation {
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    /// Match radius in metres (default 200 m).
    var radius: Double = 200

    init(name: String, latitude: Double, longitude: Double, radius: Double = 200) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }

    /// Returns true if the given coordinate falls within this location's radius.
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let point  = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let center = CLLocation(latitude: latitude, longitude: longitude)
        return point.distance(from: center) <= radius
    }
}
