//
//  HistoryView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import SwiftData
import SwiftUI

// MARK: - History List

struct HistoryView: View {
    @Query(sort: \DriveSession.startDate, order: .reverse) private var sessions: [DriveSession]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "car.fill",
                    description: Text("Start a tracking session to record your drive.")
                )
            } else {
                ForEach(sessions) { session in
                    NavigationLink(destination: DriveSessionView(session: session)) {
                        SessionRowView(session: session)
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { modelContext.delete(sessions[$0]) }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !sessions.isEmpty { EditButton() }
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: DriveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            HStack(spacing: 14) {
                Label(formatDuration(session.durationSeconds), systemImage: "clock")
                Label(formatDistance(session.totalDistanceM), systemImage: "road.lanes")
                Label(formatSpeed(session.maxSpeedMps), systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s)
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func formatDistance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : String(format: "%.0f m", m)
    }

    private func formatSpeed(_ mps: Double) -> String {
        String(format: "%.0f km/h", mps * 3.6)
    }
}

// MARK: - Saved Session Detail

struct DriveSessionView: View {
    let session: DriveSession

    private var stats: SessionStats { SessionStats(restoringFrom: session) }

    var body: some View {
        List {
            let points = session.routePoints
            if points.count >= 2 {
                Section("Route") {
                    RouteMapView(track: points, peakEvents: session.peakEventsRestored)
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    SpeedLegendView(maxSpeedMps: session.maxSpeedMps)
                }
            }

            let speeds = session.speedsKph
            if !speeds.isEmpty {
                Section("Speed over time") {
                    SpeedChart(speedsKph: speeds)
                        .padding(.vertical, 4)
                }
                let alts = session.altitudesM
                if alts.contains(where: { $0 != 0 }) {
                    Section("Elevation") {
                        ElevationChart(altitudesM: alts)
                            .padding(.vertical, 4)
                    }
                }
            }

            SessionStatsContent(stats: stats)

            Section("Recording info") {
                StatusRow(label: "Route points", value: "\(session.routeLatitudes.count)")
                StatusRow(label: "Estimated data size", value: session.estimatedSizeBytes.formattedBytes)
            }
        }
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
