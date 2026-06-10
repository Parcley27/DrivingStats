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
        ScrollView {
            LazyVStack(spacing: 20) {

                // Signal Acquisition — signal bars + numeric accuracy + speed
                CardSection("Signal Acquisition") {
                    HStack(spacing: 20) {
                        // Signal bars (more bars = better accuracy)
                        VStack(spacing: 6) {
                            HStack(alignment: .bottom, spacing: 5) {
                                ForEach(0..<4) { i in
                                    let thresholds: [Double] = [30, 20, 10, 5]
                                    let lit = location.horizontalAccuracy > 0
                                             && location.horizontalAccuracy <= thresholds[i]
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(lit ? accuracyZone : Color(.systemFill))
                                        .frame(width: 10, height: CGFloat(14 + i * 10))
                                        .animation(.easeInOut(duration: 0.3), value: lit)
                                }
                            }
                            Text(location.horizontalAccuracy > 0
                                 ? String(format: "%.1f m", location.horizontalAccuracy)
                                 : "No fix")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(accuracyZone)
                        }

                        Divider().frame(height: 52)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("GPS accuracy").font(.caption).foregroundStyle(.secondary)
                            Text(accuracyDescription)
                                .font(.headline)
                                .foregroundStyle(accuracyZone)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Speed").font(.caption).foregroundStyle(.secondary)
                            Text(location.speed > 0
                                 ? String(format: "%.0f km/h", location.speed * 3.6)
                                 : "—")
                                .font(.system(.headline, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                }

                // Sensors: 2-col grid of StatusLamps
                SectionHeader("Sensors")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatusLamp(state: motion.isAvailable ? .ok : .bad, label: "Accelerometer", detail: "±8 g · 50 Hz")
                    StatusLamp(state: motion.isAvailable ? .ok : .bad, label: "Gyroscope", detail: "50 Hz")
                    StatusLamp(state: gpsAccessState, label: "GPS access", detail: gpsAccessDetail)
                    StatusLamp(state: motion.hasValidHeading ? .ok : .warn, label: "Heading lock", detail: "Needs ≥ 2 m/s")
                }

                // GPS Detail
                CardSection("GPS Detail") {
                    VStack(spacing: 0) {
                        StatRow(label: "Horizontal accuracy", value: accuracyText)
                        StatRow(label: "Speed",               value: speedText)
                        StatRow(label: "Course",              value: courseText)
                        StatRow(label: "Altitude",            value: altitudeText, isLast: true)
                    }
                }


#if DEBUG
                CardSection("Debug") {
                    VStack(spacing: 0) {
                        Toggle("Spoof GPS heading", isOn: $spoofGPSEnabled).font(.body)
                        if spoofGPSEnabled {
                            Divider().padding(.vertical, 6)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Course: \(String(format: "%.0f", spoofCourse))°")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Slider(value: $spoofCourse, in: 0...359)
                            }
                            Text("Injected at 10 m/s, 5 m accuracy. DEBUG only.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                        }
                    }
                }
#endif
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Ready to Record")
        .safeAreaInset(edge: .bottom) {
            Button(action: beginCountdown) {
                VStack(spacing: 2) {
                    Text(countdown.map { "Starting in \($0)…" } ?? "Start Recording").font(.headline)
                    if countdown == nil {
                        Text("3-second countdown").font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(.accentColor)
            .disabled(!location.hasValidFix || countdown != nil)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.regularMaterial)
        }
#if DEBUG
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard spoofGPSEnabled else { return }
            motion.injectSpoofGPS(course: spoofCourse)
        }
        .onChange(of: spoofGPSEnabled) { _, isOn in if isOn { motion.injectSpoofGPS(course: spoofCourse) } }
        .onChange(of: spoofCourse) { _, c in guard spoofGPSEnabled else { return }; motion.injectSpoofGPS(course: c) }
#endif
    }

    // MARK: - Helpers

    private var accuracyZone: Color {
        guard location.horizontalAccuracy > 0 else { return Color(.tertiaryLabel) }
        return location.horizontalAccuracy <= 5 ? .green
             : location.horizontalAccuracy <= 15 ? .orange : .red
    }

    private var accuracyDescription: String {
        guard location.horizontalAccuracy > 0 else { return "No fix" }
        if location.horizontalAccuracy <= 5  { return "Excellent" }
        if location.horizontalAccuracy <= 15 { return "Good" }
        if location.horizontalAccuracy <= 30 { return "Fair" }
        return "Poor"
    }

    private var gpsAccessState: LampState {
        switch location.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return location.hasValidFix ? .ok : .warn
        case .notDetermined: return .off
        default: return .bad
        }
    }

    private var gpsAccessDetail: String {
        switch location.authorizationStatus {
        case .authorizedWhenInUse: return "When in use"
        case .authorizedAlways:    return "Always"
        case .notDetermined:       return "Not requested"
        default:                   return "Denied"
        }
    }

    private var accuracyText: String {
        guard location.horizontalAccuracy >= 0 else { return "No fix" }
        return String(format: "%.1f m", location.horizontalAccuracy)
    }

    private var speedText: String {
        guard location.speed >= 0 else { return "No fix" }
        return String(format: "%.1f km/h", location.speed * 3.6)
    }

    private var courseText: String {
        guard location.course >= 0 else { return "No heading" }
        return String(format: "%.0f°", location.course)
    }

    private var altitudeText: String { String(format: "%.0f m", location.altitudeM) }

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
}
