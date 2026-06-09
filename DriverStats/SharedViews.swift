//
//  SharedViews.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Charts
import SwiftUI

// MARK: - Status Row

struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Speed Chart

struct SpeedChart: View {
    let speedsKph: [Double]

    private var decimated: [(index: Int, speed: Double)] {
        guard !speedsKph.isEmpty else { return [] }
        let step = max(1, speedsKph.count / 500)
        return speedsKph.indices
            .filter { $0 % step == 0 }
            .map { (index: $0, speed: speedsKph[$0]) }
    }

    private var yMax: Double { max(speedsKph.max() ?? 10, 10) * 1.15 }

    var body: some View {
        Chart(decimated, id: \.index) { point in
            AreaMark(x: .value("Time", point.index), y: .value("Speed", point.speed))
                .foregroundStyle(.blue.opacity(0.15))
            LineMark(x: .value("Time", point.index), y: .value("Speed", point.speed))
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis(.hidden)
        .chartYAxisLabel("km/h", alignment: .trailing)
        .frame(height: 110)
    }
}

// MARK: - Elevation Chart

struct ElevationChart: View {
    let altitudesM: [Double]

    private var decimated: [(index: Int, alt: Double)] {
        guard !altitudesM.isEmpty else { return [] }
        let step = max(1, altitudesM.count / 500)
        return altitudesM.indices.filter { $0 % step == 0 }.map { (index: $0, alt: altitudesM[$0]) }
    }

    private var yRange: ClosedRange<Double> {
        let mn = altitudesM.min() ?? 0
        let mx = altitudesM.max() ?? 10
        let pad = max((mx - mn) * 0.15, 5)
        return (mn - pad)...(mx + pad)
    }

    var body: some View {
        Chart(decimated, id: \.index) { point in
            AreaMark(x: .value("Time", point.index), y: .value("Altitude (m)", point.alt))
                .foregroundStyle(.brown.opacity(0.15))
            LineMark(x: .value("Time", point.index), y: .value("Altitude (m)", point.alt))
                .foregroundStyle(.brown)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartYScale(domain: yRange)
        .chartXAxis(.hidden)
        .chartYAxisLabel("m", alignment: .trailing)
        .frame(height: 80)
    }
}

// MARK: - Speed Legend

struct SpeedLegendView: View {
    let maxSpeedMps: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speed color scale")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 8)
                    .clipShape(Capsule())
                Text(String(format: "%.0f km/h", maxSpeedMps * 3.6))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var gradientColors: [Color] {
        stride(from: 0.0, through: 1.0, by: 0.05).map { t in
            Color(hue: t * (120.0 / 360.0), saturation: 1, brightness: 0.9)
        }
    }
}
