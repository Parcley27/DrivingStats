//
//  ReadinessView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Combine
import SwiftUI

struct ReadinessView: View {
    @ObservedObject var motion: MotionManager
    @ObservedObject var location: LocationManager
    @Binding var isTracking: Bool

    @State private var countdown: Int? = nil

#if DEBUG
    @State private var spoofGPSEnabled = false
    @State private var spoofCourse: Double = 90
#endif

    var body: some View {
        List {
            Section("Motion Sensors") {
                StatusRow(
                    label: "Accelerometer and gyroscope",
                    value: motion.isAvailable ? "Available" : "Not available"
                )
            }

            Section("GPS") {
                StatusRow(label: "Authorization", value: authorizationText)
                StatusRow(label: "Horizontal accuracy", value: accuracyText)
                StatusRow(label: "Speed", value: speedText)
                StatusRow(label: "Course", value: courseText)
                StatusRow(
                    label: "Course reliable",
                    value: location.isCourseReliable
                        ? "Yes"
                        : "No (need speed above \(String(format: "%.0f", LocationManager.minReliableSpeedMps)) m/s and accuracy below \(String(format: "%.0f", LocationManager.maxReliableAccuracyM)) m)"
                )
            }

            Section("Heading") {
                StatusRow(label: "Status", value: headingStatusText)
            }

            Section(
                header: Text("Session Settings"),
                footer: Text("When on, vertical spikes from road bumps and potholes are excluded from acceleration and jerk stats. They are still counted as surface events.")
            ) {
                Toggle("Exclude road surface events from stats", isOn: $motion.suppressVerticalEvents)
            }

#if DEBUG
            Section(
                header: Text("Debug"),
                footer: Text("Spoofed fixes are injected at 10 m/s, 5 m accuracy. Only available in DEBUG builds.")
            ) {
                Toggle("Spoof GPS heading", isOn: $spoofGPSEnabled)
                if spoofGPSEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Course: \(String(format: "%.0f", spoofCourse)) degrees clockwise from north")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $spoofCourse, in: 0...359)
                    }
                    .padding(.vertical, 4)
                }
            }
#endif
        }
        .navigationTitle("Driving Stats")
#if DEBUG
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard spoofGPSEnabled else { return }
            motion.injectSpoofGPS(course: spoofCourse)
        }
        .onChange(of: spoofGPSEnabled) { _, isOn in
            if isOn { motion.injectSpoofGPS(course: spoofCourse) }
        }
        .onChange(of: spoofCourse) { _, newCourse in
            guard spoofGPSEnabled else { return }
            motion.injectSpoofGPS(course: newCourse)
        }
#endif
        .safeAreaInset(edge: .bottom) {
            Button(action: beginCountdown) {
                Text(countdown.map { "Starting in \($0)..." } ?? "Start Tracking")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!location.hasValidFix || countdown != nil)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.regularMaterial)
        }
    }

    private func beginCountdown() {
        Task {
            for i in stride(from: 3, through: 1, by: -1) {
                countdown = i
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = nil
            location.startTrack()
            motion.startSession()
            isTracking = true
        }
    }

    // MARK: - Display text helpers

    private var authorizationText: String {
        switch location.authorizationStatus {
        case .notDetermined:       return "Not requested yet"
        case .denied:              return "Denied - enable location access in Settings"
        case .restricted:          return "Restricted by device policy"
        case .authorizedWhenInUse: return "Authorized (when in use only - screen off will pause GPS)"
        case .authorizedAlways:    return "Authorized (always - screen off supported)"
        @unknown default:          return "Unknown status"
        }
    }

    private var accuracyText: String {
        guard location.horizontalAccuracy >= 0 else { return "No fix" }
        return String(format: "%.1f m", location.horizontalAccuracy)
    }

    private var speedText: String {
        guard location.speed >= 0 else { return "No fix" }
        return String(format: "%.1f m/s  (%.1f km/h)", location.speed, location.speed * 3.6)
    }

    private var courseText: String {
        guard location.course >= 0 else { return "No fix" }
        return String(format: "%.1f degrees clockwise from north", location.course)
    }

    private var headingStatusText: String {
        switch motion.headingStatus {
        case .noFix:
            return "No heading established. Drive above \(String(format: "%.0f", LocationManager.minReliableSpeedMps)) m/s to get a GPS course."
        case .gpsFix(let course, let speed, let accuracy):
            return String(format: "GPS: %.1f deg, %.1f m/s, %.1f m accuracy", course, speed, accuracy)
        case .propagated(let base, let current, let age):
            return String(format: "Gyro-propagated from GPS base %.1f deg. Current estimate: %.1f deg. GPS age: %.1f s.", base, current, age)
        }
    }
}
