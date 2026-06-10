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
        Group {
            if sessions.isEmpty {
                ScrollView {
                    ContentUnavailableView(
                        "No sessions yet",
                        systemImage: "car.fill",
                        description: Text("Start a tracking session to record your drive.")
                    )
                    .padding(.top, 60)
                }
            } else {
                List {
                    // Aggregate stats + smoothness trend
                    Section {
                        VStack(spacing: 18) {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                                spacing: 10
                            ) {
                                StatCell(label: "This week",
                                         value: String(format: "%.0f", thisWeekKm),
                                         unit: "km")
                                StatCell(label: "Avg score",
                                         value: String(format: "%.0f", avgScore),
                                         accent: true)
                                StatCell(label: "Best peak",
                                         value: String(format: "%.2f", bestPeakG),
                                         unit: "g")
                                StatCell(label: "All drives",
                                         value: "\(sessions.count)")
                                StatCell(label: "Total dist",
                                         value: String(format: "%.0f", totalKm),
                                         unit: "km")
                                StatCell(label: "Total time",
                                         value: formatDuration(totalDuration))
                            }

                            if trendScores.count >= 3 {
                                CardSection("Smoothness trend",
                                            note: "last \(trendScores.count)",
                                            innerPadding: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Score 0–100 from hard events, sustained g-force, and peak jerk. Higher = smoother.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Sparkline(data: trendScores.map { Double($0) },
                                                  color: .accentColor, showFill: false, height: 44)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    }

                    // Drive cards
                    Section {
                        ForEach(sessions) { session in
                            NavigationLink(destination: DriveSessionView(session: session)) {
                                SessionCardView(session: session)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { modelContext.delete(sessions[$0]) }
                        }
                    } header: {
                        Text("Recent Drives")
                            .font(.footnote).fontWeight(.medium)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .tracking(0.3)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton().disabled(sessions.isEmpty)
            }
        }
    }

    // MARK: - Aggregates

    private var totalKm: Double {
        sessions.reduce(0) { $0 + $1.totalDistanceM } / 1000
    }

    private var thisWeekKm: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessions.filter { $0.startDate > cutoff }.reduce(0) { $0 + $1.totalDistanceM } / 1000
    }

    private var avgScore: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.smoothnessScore } / Double(sessions.count)
    }

    private var bestPeakG: Double {
        sessions.map { $0.peakNetAccel }.max() ?? 0
    }

    private var totalDuration: Double {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    private var trendScores: [Int] {
        Array(sessions.prefix(12).reversed().map { Int($0.smoothnessScore) })
    }
}

// MARK: - Drive card row

private struct SessionCardView: View {
    let session: DriveSession
    @AppStorage("ds.showDrivingScore") private var showDrivingScore = true

    var body: some View {
        HStack(spacing: 12) {
            // Mini route map thumbnail
            Group {
                if session.routePoints.count >= 2 {
                    RouteMapView(track: session.routePoints, peakEvents: [])
                        .allowsHitTesting(false)
                } else {
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: 76, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center) {
                    Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14.5, weight: .semibold))
                    Spacer()
                    if showDrivingScore {
                        ScoreRing(value: Int(session.smoothnessScore), size: 34)
                    }
                }

                HStack(spacing: 12) {
                    Text(formatDistance(session.totalDistanceM))
                    Text(formatDuration(session.durationSeconds))
                    Text("\(Int(session.maxSpeedMps * 3.6)) km/h")
                        .foregroundStyle(Color.accentColor)
                    Text(String(format: "%.2f g", session.peakNetAccel))
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                let hardTotal = session.hardAccelCount + session.hardBrakingCount + session.hardCorneringCount
                Text("\(hardTotal) hard event\(hardTotal == 1 ? "" : "s") logged")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
