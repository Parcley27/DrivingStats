//
//  SessionResultsView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import SwiftData
import SwiftUI

// MARK: - Session Result model

struct SessionResult: Identifiable {
    let id = UUID()
    let stats: SessionStats
    let track: [RoutePoint]
    let peakEvents: [PeakEvent]
}

// MARK: - Results sheet

struct SessionResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let result: SessionResult

    @State private var didSave = false

    var body: some View {
        NavigationStack {
            List {
                if result.track.count >= 2 {
                    Section("Route") {
                        RouteMapView(track: result.track, peakEvents: result.peakEvents)
                            .frame(height: 280)
                            .listRowInsets(EdgeInsets())
                    }
                    Section {
                        SpeedLegendView(maxSpeedMps: result.stats.maxSpeedMps)
                    }
                }

                if !result.track.isEmpty {
                    Section("Speed over time") {
                        SpeedChart(speedsKph: result.track.map { $0.speedMps * 3.6 })
                            .padding(.vertical, 4)
                    }
                    let alts = result.track.map(\.altitudeM)
                    if alts.contains(where: { $0 != 0 }) {
                        Section("Elevation") {
                            ElevationChart(altitudesM: alts)
                                .padding(.vertical, 4)
                        }
                    }
                }

                SessionStatsContent(stats: result.stats)

                let estimatedBytes = result.track.count * 24 + 320
                Section("Recording info") {
                    StatusRow(label: "Route points", value: "\(result.track.count)")
                    StatusRow(label: "Estimated data size", value: estimatedBytes.formattedBytes)
                }
            }
            .navigationTitle("Session Results")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                guard !didSave else { return }
                didSave = true
                modelContext.insert(DriveSession(result: result))
            }
        }
    }
}

// MARK: - Session stats display

struct SessionStatsContent: View {
    let stats: SessionStats
    private let G = 9.80665

    var body: some View {
        Section("Session: Overview") {
            StatusRow(label: "Duration",       value: formatDuration(stats.durationSeconds))
            StatusRow(label: "Moving time",    value: formatDuration(stats.movingTimeSeconds))
            StatusRow(label: "Stopping time",  value: formatDuration(stats.stoppingTimeSeconds))
            StatusRow(label: "Stops",          value: "\(stats.stopCount)")
            StatusRow(label: "Total distance", value: formatDistance(stats.totalDistanceM))
        }

        Section("Session: Velocity") {
            StatusRow(label: "Maximum",              value: formatSpeed(stats.maxSpeedMps))
            StatusRow(label: "Average (all time)",   value: formatSpeed(stats.avgSpeedMps))
            StatusRow(label: "Average (moving only)", value: formatSpeed(stats.avgMovingSpeedMps))
        }

        Section("Session: Longitudinal (forward/braking)") {
            StatusRow(label: "Peak acceleration",                     value: accel(stats.peakForward))
            StatusRow(label: "Peak braking",                          value: accel(stats.peakBraking))
            StatusRow(label: "Average (absolute)",                    value: accelAbs(stats.avgLongitudinalAbs))
            StatusRow(label: "RMS",                                   value: accelAbs(stats.rmsForward))
            StatusRow(label: "Hard acceleration events (above 0.3 g)", value: "\(stats.hardAccelCount)")
            StatusRow(label: "Hard braking events (above 0.3 g)",     value: "\(stats.hardBrakingCount)")
            StatusRow(label: "Peak jerk forward  (fastest ramp-up in acceleration)", value: jerk(stats.peakJerkForward))
            StatusRow(label: "Peak jerk braking  (fastest ramp-up in deceleration)", value: jerk(stats.peakJerkBraking))
            StatusRow(label: "Average jerk (absolute)",               value: jerkAbs(stats.avgJerkLongitudinalAbs))
        }

        Section("Session: Lateral (left/right)") {
            StatusRow(label: "Peak right turn",                  value: accel(stats.peakRight))
            StatusRow(label: "Peak left turn",                   value: accel(stats.peakLeft))
            StatusRow(label: "Average (absolute)",               value: accelAbs(stats.avgLateralAbs))
            StatusRow(label: "RMS",                              value: accelAbs(stats.rmsLateral))
            StatusRow(label: "Hard cornering events (above 0.3 g)", value: "\(stats.hardCorneringCount)")
            StatusRow(label: "Peak jerk right",                  value: jerk(stats.peakJerkRight))
            StatusRow(label: "Peak jerk left",                   value: jerk(stats.peakJerkLeft))
            StatusRow(label: "Average jerk (absolute)",          value: jerkAbs(stats.avgJerkLateralAbs))
        }

        Section("Session: Vertical (bump/dip)") {
            StatusRow(label: "Surface events detected (bumps/potholes)", value: "\(stats.surfaceEventCount)")
            StatusRow(label: "Peak upward",           value: accel(stats.peakUp))
            StatusRow(label: "Peak downward",         value: accel(stats.peakDown))
            StatusRow(label: "Average (absolute)",    value: accelAbs(stats.avgVerticalAbs))
            StatusRow(label: "RMS",                   value: accelAbs(stats.rmsVertical))
            StatusRow(label: "Peak jerk upward",      value: jerk(stats.peakJerkUp))
            StatusRow(label: "Peak jerk downward",    value: jerk(stats.peakJerkDown))
            StatusRow(label: "Average jerk (absolute)", value: jerkAbs(stats.avgJerkVerticalAbs))
        }

        Section("Session: Net Magnitude") {
            StatusRow(label: "Peak acceleration  (sqrt of f\u{00B2} + l\u{00B2} + v\u{00B2})", value: accelAbs(stats.peakNetAccel))
            StatusRow(label: "Average acceleration", value: accelAbs(stats.avgNetAccel))
            StatusRow(label: "RMS acceleration",     value: accelAbs(stats.rmsNet))
            StatusRow(label: "Peak jerk  (sqrt of jerk_f\u{00B2} + jerk_l\u{00B2} + jerk_v\u{00B2})", value: jerkAbs(stats.peakNetJerk))
            StatusRow(label: "Average jerk",         value: jerkAbs(stats.avgNetJerk))
        }
    }

    // MARK: - Formatting helpers

    private func accel(_ val: Double) -> String {
        String(format: "%+.4f g  (%+.3f m/s\u{00B2})", val, val * G)
    }

    private func accelAbs(_ val: Double) -> String {
        String(format: "%.4f g  (%.3f m/s\u{00B2})", val, val * G)
    }

    private func jerk(_ val: Double) -> String {
        String(format: "%+.3f g/s  (%+.3f m/s\u{00B3})", val, val * G)
    }

    private func jerkAbs(_ val: Double) -> String {
        String(format: "%.3f g/s  (%.3f m/s\u{00B3})", val, val * G)
    }

    private func formatSpeed(_ mps: Double) -> String {
        String(format: "%.2f m/s  (%.1f km/h)", mps, mps * 3.6)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.2f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }
}
