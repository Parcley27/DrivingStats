//
//  SensorsView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Charts
import CoreMotion
import SwiftUI

// MARK: - Sensors Tab

struct SensorsView: View {
    @ObservedObject var motion: MotionManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GravityBallView(gravity: motion.currentGravity, isStable: motion.isStable)
                    .padding(.top, 8)

                HStack(spacing: 6) {
                    Circle()
                        .fill(motion.isStable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(motion.isStable ? "Stable" : "Moving")
                        .font(.subheadline)
                        .foregroundStyle(motion.isStable ? .green : .orange)
                }
                .animation(.easeInOut(duration: 0.2), value: motion.isStable)

                if motion.recentSamples.isEmpty {
                    Text("Waiting for GPS heading before recording acceleration.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    VStack(spacing: 16) {
                        AccelChart(
                            title: "Longitudinal  (positive = forward, negative = braking)",
                            samples: motion.recentSamples,
                            value: \.forward,
                            color: .blue
                        )
                        AccelChart(
                            title: "Lateral  (positive = right turn, negative = left turn)",
                            samples: motion.recentSamples,
                            value: \.lateral,
                            color: .green
                        )
                        AccelChart(
                            title: "Vertical  (positive = bump up, negative = dip down)",
                            samples: motion.recentSamples,
                            value: \.vertical,
                            color: .orange
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("Live Sensors")
    }
}

// MARK: - Acceleration Chart

private struct AccelChart: View {
    let title: String
    let samples: [AccelerationSample]
    let value: KeyPath<AccelerationSample, Double>
    let color: Color

    private var xDomain: ClosedRange<Double> {
        guard let last = samples.last else { return 0...30 }
        return max(0, last.elapsedSeconds - 30)...last.elapsedSeconds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time (s)", sample.elapsedSeconds),
                        y: .value("g", sample[keyPath: value])
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: -2.0...2.0)
            .chartXAxisLabel("seconds")
            .chartYAxisLabel("g")
            .frame(height: 110)
        }
    }
}

// MARK: - Gravity Ball View

/// A circular level indicator. The ball rolls toward the low side of the phone,
/// like a bubble level in reverse. Green = stable, orange = moving.
/// Axes: gravity.x = right, gravity.y = up (in portrait), gravity.z = toward user.
struct GravityBallView: View {
    let gravity: CMAcceleration?
    let isStable: Bool

    private let containerSize: CGFloat = 200
    private let ballDiameter: CGFloat = 28

    private var ballOffset: CGSize {
        guard let g = gravity else { return .zero }
        let maxRadius = containerSize / 2 - ballDiameter / 2 - 4
        let rawX = CGFloat(g.x) * maxRadius
        let rawY = CGFloat(-g.y) * maxRadius    // flip Y: gravity.y positive means phone top tilts up
        let dist = sqrt(rawX * rawX + rawY * rawY)
        if dist > maxRadius {
            let scale = maxRadius / dist
            return CGSize(width: rawX * scale, height: rawY * scale)
        }
        return CGSize(width: rawX, height: rawY)
    }

    private var ballColor: Color { isStable ? .green : .orange }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.08))
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1.5)
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: containerSize, height: 1)
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 1, height: containerSize)
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                .frame(width: 44, height: 44)
            Circle()
                .fill(ballColor)
                .shadow(color: ballColor.opacity(0.5), radius: 8)
                .frame(width: ballDiameter, height: ballDiameter)
                .offset(ballOffset)
                .animation(.spring(response: 0.15, dampingFraction: 0.7), value: ballOffset)
        }
        .frame(width: containerSize, height: containerSize)
    }
}
