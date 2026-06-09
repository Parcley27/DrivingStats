//
//  TrackingView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import SwiftUI

struct TrackingView: View {
    @ObservedObject var motion: MotionManager
    @ObservedObject var location: LocationManager
    @Binding var isTracking: Bool

    @State private var sessionResult: SessionResult? = nil

    private let G = 9.80665

    var body: some View {
        List {
            Section("GPS") {
                StatusRow(label: "Speed", value: speedText)
                StatusRow(label: "Horizontal accuracy", value: accuracyText)
                StatusRow(label: "Course", value: courseText)
            }

            Section("Heading Source") {
                Text(headingStatusText)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Live Acceleration") {
                if let a = motion.displayAcceleration {
                    StatusRow(label: "Forward  (+ = accelerating, - = braking)", value: accel(a.forward))
                    StatusRow(label: "Lateral  (+ = right turn, - = left turn)",  value: accel(a.lateral))
                    StatusRow(label: "Vertical  (+ = bump up, - = dip down)",     value: accel(a.vertical))
                } else {
                    Text("Waiting for GPS heading before decomposing acceleration.")
                        .foregroundStyle(.secondary)
                }
            }

            if let s = motion.sessionStats, s.accelCount > 0 {
                SessionStatsContent(stats: s)
            }
        }
        .navigationTitle("Tracking")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Stop") {
                    motion.endSession()
                    if let stats = motion.sessionStats {
                        sessionResult = SessionResult(
                            stats: stats,
                            track: location.trackPoints,
                            peakEvents: motion.peakEvents
                        )
                    }
                }
            }
        }
        .sheet(item: $sessionResult, onDismiss: { isTracking = false }) { result in
            SessionResultsView(result: result)
        }
    }

    // MARK: - Formatting

    private func accel(_ val: Double) -> String {
        String(format: "%+.4f g  (%+.3f m/s\u{00B2})", val, val * G)
    }

    private var speedText: String {
        guard location.speed >= 0 else { return "No fix" }
        return String(format: "%.2f m/s  (%.1f km/h)", location.speed, location.speed * 3.6)
    }

    private var accuracyText: String {
        guard location.horizontalAccuracy >= 0 else { return "No fix" }
        return String(format: "%.1f m", location.horizontalAccuracy)
    }

    private var courseText: String {
        guard location.course >= 0 else { return "No fix" }
        return String(format: "%.1f degrees clockwise from north", location.course)
    }

    private var headingStatusText: String {
        switch motion.headingStatus {
        case .noFix:
            return "No heading established"
        case .gpsFix(let course, let speed, let accuracy):
            return String(format: "GPS: %.1f deg at %.2f m/s, %.1f m accuracy", course, speed, accuracy)
        case .propagated(let base, let current, let age):
            return String(format: "Gyro-propagated\nBase GPS: %.1f deg\nCurrent estimate: %.1f deg\nGPS age: %.1f s", base, current, age)
        }
    }
}
