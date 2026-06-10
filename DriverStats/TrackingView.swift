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

    private var stats: SessionStats? { motion.sessionStats }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {

                // Speed hero
                CardSection(innerPadding: 10) {
                    HStack {
                        Spacer()
                        Dial(value: max(0, location.speed * 3.6),
                             max: 200, unit: "km/h", label: "speed",
                             size: 190, zone: .accentColor, bigValue: true)
                        Spacer()
                    }
                }

                // g-g Diagram + live readout
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader("g-g Diagram", note: "live").padding(.bottom, 7)
                    HStack(alignment: .center, spacing: 14) {
                        GGDiagram(points: ggTrail, gmax: 0.7, size: 150,
                                  showTrail: true, current: ggCurrent)
                        VStack(spacing: 0) {
                            StatRow(label: "Forward",
                                    value: motion.displayAcceleration.map { signedG($0.forward) } ?? "—")
                            StatRow(label: "Lateral",
                                    value: motion.displayAcceleration.map { signedG($0.lateral) } ?? "—")
                            StatRow(label: "Vertical",
                                    value: motion.displayAcceleration.map { signedG($0.vertical) } ?? "—")
                            StatRow(label: "Net",
                                    value: motion.displayAcceleration.map { netGStr($0) } ?? "—",
                                    isLast: true)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Session stats
                CardSection("Session") {
                    VStack(spacing: 0) {
                        StatRow(label: "Distance",
                                value: stats.map { formatDistance($0.totalDistanceM) } ?? "—")
                        StatRow(label: "Moving time",
                                value: stats.map { formatDuration($0.movingTimeSeconds) } ?? "—")
                        StatRow(label: "Max speed",
                                value: stats.map { String(format: "%.0f km/h", $0.maxSpeedMps * 3.6) } ?? "—")
                        StatRow(label: "Stops",
                                value: stats.map { "\($0.stopCount)" } ?? "—", isLast: true)
                    }
                }

                // Hard events
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader("Hard Events", note: String(format: "threshold %.2f g", motion.hardThresholdG)).padding(.bottom, 7)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                        spacing: 10
                    ) {
                        StatCell(label: "Accel",  value: "\(stats?.hardAccelCount ?? 0)",    accent: true)
                        StatCell(label: "Brake",  value: "\(stats?.hardBrakingCount ?? 0)",  accent: true)
                        StatCell(label: "Corner", value: "\(stats?.hardCorneringCount ?? 0)", accent: true)
                    }
                }

                // Heading source
                CardSection("Heading Source") {
                    VStack(spacing: 0) {
                        StatRow(label: "Mode",               value: headingMode)
                        StatRow(label: "Base GPS / estimate", value: headingBaseEst)
                        StatRow(label: "GPS age",            value: headingGpsAge, isLast: true)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Driving")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(stats.map { "Recording · \(formatDuration($0.durationSeconds))" } ?? "Recording")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("REC")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: stopSession) {
                Text("Stop & Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .sheet(item: $sessionResult, onDismiss: { isTracking = false }) { result in
            SessionResultsView(result: result)
        }
    }

    // MARK: - Data

    private var ggTrail: [GGPoint] {
        motion.recentSamples.map { GGPoint(lat: $0.lateral, fwd: $0.forward) }
    }

    private var ggCurrent: GGPoint? {
        guard let a = motion.displayAcceleration else { return nil }
        return GGPoint(lat: a.lateral, fwd: a.forward)
    }

    private func signedG(_ v: Double) -> String { String(format: "%+.2f g", v) }

    private func netGStr(_ a: AccelerationComponents) -> String {
        let net = (a.forward * a.forward + a.lateral * a.lateral + a.vertical * a.vertical).squareRoot()
        return String(format: "%.2f g", net)
    }

    // MARK: - Heading

    private var headingMode: String {
        switch motion.headingStatus {
        case .noFix: return "No fix"
        case .gpsFix: return "GPS direct"
        case .propagated: return "Gyro-propagated"
        }
    }

    private var headingBaseEst: String {
        switch motion.headingStatus {
        case .noFix: return "—"
        case .gpsFix(let c, _, _): return String(format: "%.0f°", c)
        case .propagated(let b, let cur, _): return String(format: "%.0f° / %.0f°", b, cur)
        }
    }

    private var headingGpsAge: String {
        switch motion.headingStatus {
        case .noFix: return "—"
        case .gpsFix: return "< 1.5 s"
        case .propagated(_, _, let age): return String(format: "%.1f s", age)
        }
    }

    private func stopSession() {
        motion.endSession()
        guard let stats = motion.sessionStats else { return }
        sessionResult = SessionResult(
            stats: stats,
            track: location.trackPoints,
            peakEvents: motion.peakEvents,
            ggSamples: motion.ggSamples
        )
    }
}
