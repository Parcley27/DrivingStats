//
//  SessionResultsView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Charts
import MapKit
import SwiftData
import SwiftUI

// MARK: - Session Result model

struct SessionResult: Identifiable {
    let id = UUID()
    let stats: SessionStats
    let track: [RoutePoint]
    let peakEvents: [PeakEvent]
    var ggSamples: [GGPoint] = []
}

// MARK: - Results sheet (shown immediately after Stop)

struct SessionResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("ds.showDrivingScore") private var showDrivingScore = true
    let result: SessionResult

    @State private var didSave = false

    var body: some View {
        NavigationStack {
            DriveSessionContent(
                track: result.track,
                peakEvents: result.peakEvents,
                stats: result.stats,
                ggSamples: result.ggSamples
            )
            .navigationTitle("Drive Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showDrivingScore {
                    ToolbarItem(placement: .navigationBarLeading) {
                        ScoreRing(value: scoreFrom(result.stats), label: "Smooth", size: 44)
                    }
                }
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

    private func scoreFrom(_ s: SessionStats) -> Int {
        let hard = Double(s.hardAccelCount + s.hardBrakingCount + s.hardCorneringCount)
        let v = 100 - 4 * hard - 30 * min(max(s.rmsNet, 0), 1) - 8 * min(max(s.peakNetJerk / 10, 0), 1)
        return Int(max(0, min(100, v)))
    }
}

// MARK: - Saved session detail (opened from History)

struct DriveSessionView: View {
    let session: DriveSession
    @AppStorage("ds.showDrivingScore") private var showDrivingScore = true
    private var stats: SessionStats { SessionStats(restoringFrom: session) }

    var body: some View {
        DriveSessionContent(
            track: session.routePoints,
            peakEvents: session.peakEventsRestored,
            stats: stats,
            ggSamples: []
        )
        .navigationTitle("Drive Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showDrivingScore {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ScoreRing(value: Int(session.smoothnessScore), label: "Smooth", size: 42)
                }
            }
        }
    }
}

// MARK: - Shared visual content

private struct DriveSessionContent: View {
    let track: [RoutePoint]
    let peakEvents: [PeakEvent]
    let stats: SessionStats
    let ggSamples: [GGPoint]

    private let G = 9.80665

    private var gmax: Double { max(stats.peakNetAccel * 1.3, 0.5) }

    // Full scatter when available; fall back to 4 axis-peak markers for stored sessions
    private var ggPoints: [GGPoint] {
        if !ggSamples.isEmpty { return ggSamples }
        guard stats.peakNetAccel > 0 else { return [] }
        return [
            GGPoint(lat: 0,               fwd: stats.peakForward,  isPeak: true),
            GGPoint(lat: 0,               fwd: stats.peakBraking,  isPeak: true),
            GGPoint(lat: stats.peakRight,  fwd: 0,                 isPeak: true),
            GGPoint(lat: stats.peakLeft,   fwd: 0,                 isPeak: true),
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {

                // Route map + speed legend + sparklines (route group)
                if track.count >= 2 {
                    VStack(spacing: 0) {
                        RouteMapView(track: track, peakEvents: peakEvents)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        speedLegend.padding(.top, 10)
                    }
                }

                // Two dials: top speed + peak net g
                HStack(spacing: 10) {
                    CardSection(innerPadding: 6) {
                        HStack { Spacer()
                            Dial(value: stats.maxSpeedMps * 3.6, max: 200,
                                 unit: "km/h", label: "top speed",
                                 size: 126, zone: .accentColor)
                        Spacer() }
                    }
                    CardSection(innerPadding: 6) {
                        HStack { Spacer()
                            Dial(value: stats.peakNetAccel, max: 1,
                                 unit: "g", label: "peak net",
                                 size: 126, zone: .orange, decimals: 2)
                        Spacer() }
                    }
                }

                if !track.isEmpty {
                    let speeds = track.map { $0.speedMps * 3.6 }
                    CardSection("Speed over time",
                                note: String(format: "max %.0f km/h", speeds.max() ?? 0),
                                innerPadding: 12) {
                        Sparkline(data: speeds, color: .accentColor, showFill: true)
                    }
                    let alts = track.map { $0.altitudeM }
                    if alts.contains(where: { $0 != 0 }) {
                        CardSection("Elevation",
                                    note: String(format: "+%.0f / −%.0f m", elevGain(alts), elevLoss(alts)),
                                    innerPadding: 12) {
                            Sparkline(data: alts, color: .green, showFill: true)
                        }
                    }
                }

                // Overview 3×2 StatCells
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    StatCell(label: "Duration",
                             value: formatDuration(stats.durationSeconds),
                             sub: "moving \(formatDuration(stats.movingTimeSeconds))")
                    StatCell(label: "Distance",
                             value: String(format: "%.1f", stats.totalDistanceM / 1000),
                             unit: "km")
                    StatCell(label: "Avg moving",
                             value: String(format: "%.0f", stats.avgMovingSpeedMps * 3.6),
                             unit: "km/h")
                    StatCell(label: "Stops",
                             value: "\(stats.stopCount)",
                             sub: "\(formatDuration(stats.stoppingTimeSeconds)) idle")
                    StatCell(label: "Hard events",
                             value: "\(stats.hardAccelCount + stats.hardBrakingCount + stats.hardCorneringCount)",
                             sub: "\(stats.hardAccelCount)A · \(stats.hardBrakingCount)B · \(stats.hardCorneringCount)C",
                             accent: true)
                    StatCell(label: "Surface", value: "\(stats.surfaceEventCount)", sub: "bumps")
                }

                // g-g Envelope
                if !ggPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader("g-g Envelope", note: "peak markers").padding(.bottom, 7)
                        CardSection(innerPadding: 10) {
                            HStack { Spacer()
                                GGDiagram(points: ggPoints, gmax: gmax, size: 200, showEnvelope: true)
                            Spacer() }
                        }
                    }
                }

                // Longitudinal detail
                CardSection("Longitudinal", note: "m/s² · g") {
                    VStack(spacing: 0) {
                        StatRow(label: "Peak acceleration",
                                value: fg(stats.peakForward, signed: true),
                                si: fm(stats.peakForward, signed: true))
                        StatRow(label: "Peak braking",
                                value: fg(stats.peakBraking, signed: true),
                                si: fm(stats.peakBraking, signed: true))
                        StatRow(label: "Average |a|",
                                value: fg(stats.avgLongitudinalAbs),
                                si: fm(stats.avgLongitudinalAbs))
                        StatRow(label: "RMS",
                                value: fg(stats.rmsForward),
                                si: fm(stats.rmsForward))
                        StatRow(label: "Hard accel / brake",
                                value: "\(stats.hardAccelCount) / \(stats.hardBrakingCount)")
                        StatRow(label: "Peak jerk fwd / brake",
                                value: String(format: "%.1f / %.1f g/s",
                                              stats.peakJerkForward, abs(stats.peakJerkBraking)),
                                isLast: true)
                    }
                }

                // Lateral detail
                CardSection("Lateral", note: "m/s² · g") {
                    VStack(spacing: 0) {
                        StatRow(label: "Peak right",
                                value: fg(stats.peakRight, signed: true),
                                si: fm(stats.peakRight, signed: true))
                        StatRow(label: "Peak left",
                                value: fg(stats.peakLeft, signed: true),
                                si: fm(stats.peakLeft, signed: true))
                        StatRow(label: "Average |a|",
                                value: fg(stats.avgLateralAbs),
                                si: fm(stats.avgLateralAbs))
                        StatRow(label: "RMS",
                                value: fg(stats.rmsLateral),
                                si: fm(stats.rmsLateral))
                        StatRow(label: "Hard cornering",
                                value: "\(stats.hardCorneringCount)", isLast: true)
                    }
                }

                // Vertical & Net detail
                CardSection("Vertical & Net", note: "m/s² · g") {
                    VStack(spacing: 0) {
                        StatRow(label: "Surface events", value: "\(stats.surfaceEventCount)")
                        StatRow(label: "Peak up / down",
                                value: String(format: "%+.2f / %.2f g",
                                              stats.peakUp, stats.peakDown))
                        StatRow(label: "Net peak acceleration",
                                value: fg(stats.peakNetAccel),
                                si: fm(stats.peakNetAccel))
                        StatRow(label: "Net peak jerk",
                                value: String(format: "%.1f g/s", stats.peakNetJerk),
                                si: String(format: "%.1f", stats.peakNetJerk * G),
                                isLast: true)
                    }
                }

            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Helpers

    private var speedLegend: some View {
        HStack(spacing: 8) {
            Text("0")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
            LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 0.05).map { t in
                    Color(hue: t * (120.0 / 360.0), saturation: 1, brightness: 0.9)
                },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 6).clipShape(Capsule())
            Text(String(format: "%.0f km/h", stats.maxSpeedMps * 3.6))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func fg(_ v: Double, signed: Bool = false) -> String {
        signed ? String(format: "%+.2f g", v) : String(format: "%.2f g", v)
    }
    private func fm(_ v: Double, signed: Bool = false) -> String {
        signed ? String(format: "%+.2f m/s²", v * G) : String(format: "%.2f m/s²", v * G)
    }

    private func elevGain(_ alts: [Double]) -> Double {
        var g = 0.0
        for i in 1..<alts.count where alts[i] > alts[i - 1] { g += alts[i] - alts[i - 1] }
        return g
    }
    private func elevLoss(_ alts: [Double]) -> Double {
        var l = 0.0
        for i in 1..<alts.count where alts[i] < alts[i - 1] { l += alts[i - 1] - alts[i] }
        return l
    }
}
