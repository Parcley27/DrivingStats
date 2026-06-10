//
//  SensorsView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Charts
import SwiftUI

struct SensorsView: View {
    @ObservedObject var motion: MotionManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {

                // Gravity Level: bubble + gx/gy/gz cells
                CardSection("Gravity Level") {
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            GravityBubble(
                                forward: motion.displayAcceleration?.forward ?? 0,
                                lateral: motion.displayAcceleration?.lateral ?? 0,
                                gmax: 0.6, size: 176,
                                isStable: motion.isStable
                            )
                            Spacer()
                        }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                            spacing: 10
                        ) {
                            StatCell(label: "gx (lat)",  value: gfmt(motion.displayAcceleration?.lateral))
                            StatCell(label: "gy (fwd)",  value: gfmt(motion.displayAcceleration?.forward))
                            StatCell(label: "gz (vert)", value: gfmt(motion.displayAcceleration?.vertical))
                        }
                    }
                }

                // Acceleration Channels
                CardSection("Acceleration Channels", note: "rolling 30 s") {
                    VStack(spacing: 10) {
                        AccelStrip(title: "Longitudinal · fwd + / brake −",
                                   samples: motion.recentSamples, value: \.forward,
                                   color: .accentColor)
                        AccelStrip(title: "Lateral · right + / left −",
                                   samples: motion.recentSamples, value: \.lateral,
                                   color: .green)
                        AccelStrip(title: "Vertical · bump + / dip −",
                                   samples: motion.recentSamples, value: \.vertical,
                                   color: .orange)
                    }
                }

                // Raw Readout
                CardSection("Raw Readout") {
                    VStack(spacing: 0) {
                        StatRow(label: "Sample rate", value: "50 Hz")
                        StatRow(label: "Buffer",
                                value: "\(motion.recentSamples.count) / 300")
                        StatRow(label: "Stability",
                                value: motion.isStable ? "Stable" : "Unstable")
                        StatRow(label: "Heading status", value: headingText, isLast: true)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Sensors")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Live · 50 Hz")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(motion.isStable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(motion.isStable ? "Stable" : "Moving")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(motion.isStable ? .green : .orange)
                }
                .animation(.easeInOut(duration: 0.2), value: motion.isStable)
            }
        }
    }

    private func gfmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%+.2f", v)
    }

    private var headingText: String {
        switch motion.headingStatus {
        case .noFix: return "No fix"
        case .gpsFix(let c, _, _): return String(format: "GPS fix · %.0f°", c)
        case .propagated(_, let cur, _): return String(format: "Gyro · %.0f°", cur)
        }
    }
}
