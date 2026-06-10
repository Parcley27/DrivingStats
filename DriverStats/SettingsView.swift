//
//  SettingsView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var motion: MotionManager
    @AppStorage("ds.autoPause") private var autoPause: Bool = true
    @AppStorage("ds.backgroundRecording") private var backgroundRecording: Bool = false
    @AppStorage("ds.showDrivingScore") private var showDrivingScore: Bool = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {

                // MARK: Recording
                CardSection("Recording") {
                    VStack(spacing: 0) {
                        Toggle(isOn: $motion.suppressVerticalEvents) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Suppress road-surface spikes").font(.body)
                                Text("Bumps excluded from g-stats; still counted as surface events.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                        Divider().padding(.vertical, 6)
                        Toggle(isOn: $motion.autoSmooth) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Auto-smooth acceleration").font(.body)
                                Text("Rolling average filters sensor spikes while preserving real braking and cornering events.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                        if motion.autoSmooth {
                            Divider().padding(.vertical, 6)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Smooth window").font(.body)
                                    Spacer()
                                    Text(String(format: "%.2f s", motion.autoSmoothWindowSeconds))
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $motion.autoSmoothWindowSeconds, in: 0.10...1.0, step: 0.05)
                                    .tint(.accentColor)
                                HStack {
                                    Text("0.10 s · sensitive").font(.caption2).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text("1.0 s · smooth").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Divider().padding(.vertical, 6)
                        Toggle("Auto-pause when stopped", isOn: $autoPause)
                            .tint(.green).font(.body)
                        Divider().padding(.vertical, 6)
                        Toggle(isOn: $backgroundRecording) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Background recording").font(.body)
                                Text("Keep logging with the screen off (needs Always location access).")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                    }
                }

                // MARK: Detection Thresholds
                CardSection("Detection Thresholds") {
                    VStack(spacing: 0) {

                        // Hard events
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Hard event").font(.body)
                                    Text("Acceleration, braking, or cornering above this value is counted as a hard event.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Text(String(format: "%.2f g", motion.hardThresholdG))
                                    .font(.system(.headline, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                            }
                            Slider(value: $motion.hardThresholdG, in: 0.15...0.60, step: 0.05)
                                .tint(Color.accentColor)
                            HStack {
                                Text("0.15 g — lenient").font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                Text("0.60 g — strict").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }

                        Divider().padding(.vertical, 12)

                        // Surface events
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Road surface").font(.body)
                                    Text("Vertical spikes above this value are counted as bumps or potholes.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Text(String(format: "%.2f g", motion.surfaceThresholdG))
                                    .font(.system(.headline, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                            }
                            Slider(value: $motion.surfaceThresholdG, in: 0.20...0.80, step: 0.05)
                                .tint(Color.accentColor)
                            HStack {
                                Text("0.20 g — lenient").font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                Text("0.80 g — strict").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // MARK: Driving Score
                CardSection("Driving Score") {
                    VStack(spacing: 0) {
                        Toggle(isOn: $showDrivingScore) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Show driving score").font(.body)
                                Text("A 0–100 score summarising each drive. Starts at 100 and deducts points for hard events (−4 each), sustained g-force (up to −30), and peak jerk (up to −8). Higher is smoother.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                    }
                }

                // MARK: Reset
                CardSection("Reset") {
                    Button(role: .destructive) {
                        motion.hardThresholdG        = 0.30
                        motion.surfaceThresholdG     = 0.40
                        motion.autoSmoothWindowSeconds = 0.50
                        motion.autoSmooth            = true
                        motion.suppressVerticalEvents = true
                        autoPause            = true
                        backgroundRecording  = false
                    } label: {
                        HStack {
                            Spacer()
                            Text("Restore Defaults")
                                .font(.body)
                            Spacer()
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Settings")
    }
}
