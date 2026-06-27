//
//  SessionResultsView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Charts
import CoreLocation
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
    var rawFwd: [Float] = []
    var rawLat: [Float] = []
    var rawVert: [Float] = []
    var lapSplits: [Double] = []
}

// MARK: - Results sheet (shown immediately after Stop)

struct SessionResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let result: SessionResult

    @State private var didSave = false

    var body: some View {
        NavigationStack {
            DriveSessionContent(
                track: result.track,
                peakEvents: result.peakEvents,
                stats: result.stats,
                ggSamples: result.ggSamples,
                lapSplits: result.lapSplits,
                rawFwd: result.rawFwd,
                rawLat: result.rawLat
            )
            .navigationTitle("Drive Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                guard !didSave else { return }
                didSave = true
                let session = DriveSession(result: result)
                modelContext.insert(session)
                guard let first = result.track.first, let last = result.track.last,
                      result.track.count >= 2 else { return }
                let startCoord = first.coordinate
                let endCoord = last.coordinate
                Task {
                    await geocodePlaceNames(session: session, start: startCoord, end: endCoord)
                }
            }
        }
    }

    @MainActor
    private func geocodePlaceNames(session: DriveSession,
                                   start: CLLocationCoordinate2D,
                                   end: CLLocationCoordinate2D) async {
        session.startPlaceName = await reverseName(coordinate: start)
        session.endPlaceName = await reverseName(coordinate: end)
    }

    private func reverseName(coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        return await withCheckedContinuation { continuation in
            request.getMapItems { items, _ in
                let item = items?.first
                continuation.resume(returning: item?.addressRepresentations?.cityName)
            }
        }
    }
}

// MARK: - Saved session detail (opened from History)

struct DriveSessionView: View {
    let session: DriveSession
    private var stats: SessionStats { SessionStats(restoringFrom: session) }

    var body: some View {
        DriveSessionContent(
            track: session.routePoints,
            peakEvents: session.peakEventsRestored,
            stats: stats,
            ggSamples: session.ggPointsStored,
            lapSplits: session.lapSplitSeconds,
            dataSize: session.estimatedSizeBytes,
            rawFwd: session.rawFwd,
            rawLat: session.rawLat
        )
        .navigationTitle(session.routeLabel ?? "Drive Summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared visual content

private struct DriveSessionContent: View {
    let track: [RoutePoint]
    let peakEvents: [PeakEvent]
    let stats: SessionStats
    let ggSamples: [GGPoint]
    var lapSplits: [Double] = []
    var dataSize: Int? = nil
    var rawFwd: [Float] = []
    var rawLat: [Float] = []

    @AppStorage("ds.showDrivingScore") private var showDrivingScore = true
    @State private var showingFullscreenMap = false
    @State private var scrubFraction: Double? = nil

    private let G = 9.80665

    private var gmax: Double { max(stats.peakNetAccel * 1.3, 0.5) }

    private var scrubCoordinate: CLLocationCoordinate2D? {
        guard let frac = scrubFraction, track.count >= 2 else { return nil }
        let idx = min(track.count - 1, max(0, Int(frac * Double(track.count))))
        return track[idx].coordinate
    }

    private var smoothnessScore: Int {
        let movingMin = max(1.0, stats.movingTimeSeconds / 60)
        let hard = Double(stats.hardAccelCount + stats.hardBrakingCount + stats.hardCorneringCount)
        let hardPerMin = hard / movingMin
        let v = 100 - 20 * hardPerMin - 30 * min(max(stats.rmsNet, 0), 1) - 8 * min(max(stats.peakNetJerk / 10, 0), 1)
        return Int(max(0, min(100, v)))
    }

    private var scoreLabel: String {
        switch smoothnessScore {
        case 85...: return "Excellent"
        case 70...: return "Good"
        case 50...: return "Fair"
        default:    return "Rough"
        }
    }

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
        List {

            // Route map + speed legend
            if track.count >= 2 {
                Section {
                    VStack(spacing: 0) {
                        RouteMapView(track: track, peakEvents: peakEvents,
                                     scrubCoordinate: scrubCoordinate,
                                     onScrubFractionChanged: { scrubFraction = $0 })
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(7)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                                    .padding(8)
                            }
                            .onTapGesture { showingFullscreenMap = true }
                        speedLegend.padding(.top, 10)
                    }
                }
                .sheet(isPresented: $showingFullscreenMap) {
                    NavigationStack {
                        FullscreenRouteView(
                            track: track,
                            peakEvents: peakEvents,
                            rawFwd: rawFwd,
                            rawLat: rawLat
                        )
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Route")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingFullscreenMap = false }
                            }
                        }
                    }
                }
            }

            // Two dials: top speed + peak net g
            Section {
                HStack(spacing: 16) {
                    Spacer()
                    Dial(value: stats.maxSpeedMps * 3.6, max: 200,
                         unit: "km/h", label: "top speed",
                         size: 130, zone: .accentColor)
                    Spacer()
                    Dial(value: stats.peakNetAccel, max: 1,
                         unit: "g", label: "peak net",
                         size: 130, zone: .orange, decimals: 2)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Speed + elevation charts
            if !track.isEmpty {
                let speeds = track.map { $0.speedMps * 3.6 }
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Speed over time").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let frac = scrubFraction, !speeds.isEmpty {
                                let idx = min(speeds.count - 1, max(0, Int(frac * Double(speeds.count))))
                                Text(String(format: "%.0f km/h", speeds[idx]))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Text(String(format: "max %.0f km/h", speeds.max() ?? 0))
                                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                            }
                        }
                        ScrubSpeedChart(data: speeds, color: .accentColor, showFill: true,
                                        scrubFraction: $scrubFraction)
                        if let frac = scrubFraction, !rawFwd.isEmpty, rawFwd.count == rawLat.count {
                            let rawIdx = min(rawFwd.count - 1, max(0, Int(frac * Double(rawFwd.count))))
                            HStack(spacing: 4) {
                                Text(String(format: "%+.2f g", Double(rawFwd[rawIdx])))
                                    .foregroundStyle(.blue)
                                Text("fwd").foregroundStyle(.tertiary)
                                Text("·").foregroundStyle(.quaternary)
                                Text(String(format: "%+.2f g", Double(rawLat[rawIdx])))
                                    .foregroundStyle(.orange)
                                Text("lat").foregroundStyle(.tertiary)
                            }
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 1)
                        }
                    }
                    let alts = smoothElevationGlitches(track.map { $0.altitudeM })
                    if alts.contains(where: { $0 != 0 }) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Elevation").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let frac = scrubFraction, !alts.isEmpty {
                                    let idx = min(alts.count - 1, max(0, Int(frac * Double(alts.count))))
                                    Text(String(format: "%.0f m", alts[idx]))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.green)
                                } else {
                                    Text(String(format: "+%.0f / −%.0f m", elevGain(alts), elevLoss(alts)))
                                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                                }
                            }
                            ScrubSpeedChart(data: alts, color: .green, showFill: true,
                                            zeroBased: false, scrubFraction: $scrubFraction)
                        }
                    }
                }
            }

            // Overview stat cells
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    StatCell(label: "Duration",
                             value: formatDuration(stats.durationSeconds),
                             sub: "moving \(formatDuration(stats.movingTimeSeconds))")
                    StatCell(label: "Distance",
                             value: String(format: "%.1f", stats.totalDistanceM / 1000),
                             unit: "km")
                    StatCell(label: "Avg speed",
                             value: String(format: "%.0f", stats.avgSpeedMps * 3.6),
                             unit: "km/h",
                             sub: "moving \(Int(stats.avgMovingSpeedMps * 3.6))")
                    StatCell(label: "Stops",
                             value: "\(stats.stopCount)",
                             sub: "\(formatDuration(stats.stoppingTimeSeconds)) idle")
                    StatCell(label: "Hard events",
                             value: "\(stats.hardAccelCount + stats.hardBrakingCount + stats.hardCorneringCount)",
                             sub: "\(stats.hardAccelCount)A · \(stats.hardBrakingCount)B · \(stats.hardCorneringCount)C",
                             accent: true)
                    StatCell(label: "Surface", value: "\(stats.surfaceEventCount)", sub: "bumps")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            // Laps — only shown when the driver completed at least one circuit
            if !lapSplits.isEmpty {
                Section {
                    Text("Laps use the recording start point as the finish line — GPS accuracy and circuit shape affect detection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let fastest = lapSplits.min() ?? 0
                    let slowest = lapSplits.max() ?? 0
                    ForEach(lapSplits.indices, id: \.self) { i in
                        let t = lapSplits[i]
                        LabeledContent("Lap \(i + 1)") {
                            Text(formatDuration(t))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(
                                    lapSplits.count > 1 && t == fastest ? Color.green
                                    : lapSplits.count > 1 && t == slowest ? Color.orange
                                    : Color.secondary
                                )
                        }
                    }
                    if lapSplits.count >= 2 {
                        LabeledContent("Fastest") {
                            Text(formatDuration(fastest))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        LabeledContent("Slowest") {
                            Text(formatDuration(slowest))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    sectionHeader("Laps", note: "\(lapSplits.count) \(lapSplits.count == 1 ? "lap" : "laps")")
                }
            }

            // Session timing + data size
            Section {
                LabeledContent("Started", value: stats.startDate.formatted(date: .abbreviated, time: .shortened))
                if let end = stats.endDate {
                    LabeledContent("Ended", value: end.formatted(date: .abbreviated, time: .shortened))
                }
                if let size = dataSize {
                    LabeledContent("Recorded data", value: size.formattedBytes)
                }
            }

            // Smoothness score
            if showDrivingScore {
                Section("Smoothness Score") {
                    HStack(spacing: 16) {
                        ScoreRing(value: smoothnessScore, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scoreLabel).font(.title3).fontWeight(.semibold)
                            Text("Hard events / min, sustained g-force, peak jerk.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            // g-g Envelope
            if !ggPoints.isEmpty {
                Section {
                    HStack { Spacer()
                        GGDiagram(points: ggPoints, gmax: gmax, size: 200, showEnvelope: true)
                    Spacer() }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("g-g Envelope").textCase(nil)
                        Spacer()
                        Text("peak markers").font(.caption2.monospaced()).foregroundStyle(.tertiary).textCase(nil)
                    }
                }
            }

            // Longitudinal
            Section {
                statRow("Peak acceleration",   fg(stats.peakForward, signed: true),  fm(stats.peakForward, signed: true))
                statRow("Peak braking",        fg(stats.peakBraking, signed: true),  fm(stats.peakBraking, signed: true))
                statRow("Average |a|",         fg(stats.avgLongitudinalAbs),         fm(stats.avgLongitudinalAbs))
                statRow("RMS",                 fg(stats.rmsForward),                 fm(stats.rmsForward))
                LabeledContent("Hard accel / brake",       value: "\(stats.hardAccelCount) / \(stats.hardBrakingCount)")
                LabeledContent("Avg jerk |longitudinal|",  value: String(format: "%.2f g/s", stats.avgJerkLongitudinalAbs))
                LabeledContent("Peak jerk fwd / brake",    value: String(format: "%.1f / %.1f g/s", stats.peakJerkForward, abs(stats.peakJerkBraking)))
            } header: {
                sectionHeader("Longitudinal", note: "m/s² · g")
            }

            // Lateral
            Section {
                statRow("Peak right",      fg(stats.peakRight, signed: true),  fm(stats.peakRight, signed: true))
                statRow("Peak left",       fg(stats.peakLeft, signed: true),   fm(stats.peakLeft, signed: true))
                statRow("Average |a|",     fg(stats.avgLateralAbs),            fm(stats.avgLateralAbs))
                statRow("RMS",             fg(stats.rmsLateral),               fm(stats.rmsLateral))
                LabeledContent("Hard cornering",      value: "\(stats.hardCorneringCount)")
                LabeledContent("Avg jerk |lateral|",  value: String(format: "%.2f g/s", stats.avgJerkLateralAbs))
                LabeledContent("Peak jerk R / L",     value: String(format: "%.1f / %.1f g/s", stats.peakJerkRight, abs(stats.peakJerkLeft)))
            } header: {
                sectionHeader("Lateral", note: "m/s² · g")
            }

            // Vertical & Net
            Section {
                LabeledContent("Surface events", value: "\(stats.surfaceEventCount)")
                LabeledContent("Peak up / down",  value: String(format: "%+.2f / %.2f g", stats.peakUp, stats.peakDown))
                statRow("Average |vertical|",    fg(stats.avgVerticalAbs),   fm(stats.avgVerticalAbs))
                statRow("RMS vertical",          fg(stats.rmsVertical),      fm(stats.rmsVertical))
                statRow("Net peak acceleration", fg(stats.peakNetAccel),     fm(stats.peakNetAccel))
                statRow("Net avg acceleration",  fg(stats.avgNetAccel),      fm(stats.avgNetAccel))
                statRow("Net RMS",               fg(stats.rmsNet),           fm(stats.rmsNet))
                LabeledContent("Net peak jerk",  value: String(format: "%.1f g/s  (%.1f m/s³)", stats.peakNetJerk, stats.peakNetJerk * G))
            } header: {
                sectionHeader("Vertical & Net", note: "m/s² · g")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String, _ si: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Text(si).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                Text(value).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).textCase(nil)
            Spacer()
            Text(note).font(.caption2.monospaced()).foregroundStyle(.tertiary).textCase(nil)
        }
    }

    // MARK: - Helpers

    private var speedLegend: some View {
        HStack(spacing: 8) {
            Text("0")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
            LinearGradient(
                colors: [.red, .orange, .yellow, .green],
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

// MARK: - Elevation glitch suppression

/// Removes transient sensor spikes where altitude deviates by more than `threshold` metres
/// from the preceding value AND recovers to within `threshold` metres within `windowSize`
/// samples. The affected samples are replaced with linear interpolation between the last
/// clean value before the spike and the first clean value after it.
private func smoothElevationGlitches(_ alts: [Double],
                                      threshold: Double = 15.0,
                                      windowSize: Int = 10) -> [Double] {
    guard alts.count > 2 else { return alts }
    var result = alts
    var i = 1
    while i < result.count {
        let baseline = result[i - 1]
        guard abs(result[i] - baseline) > threshold else { i += 1; continue }
        // Spike detected — scan ahead for recovery within windowSize samples
        let limit = min(i + windowSize, result.count)
        var recoveryIdx: Int? = nil
        for j in (i + 1)..<limit {
            if abs(result[j] - baseline) <= threshold {
                recoveryIdx = j
                break
            }
        }
        guard let end = recoveryIdx else { i += 1; continue }
        // Linearly interpolate from index (i-1) to index end
        let startVal = result[i - 1]
        let endVal   = result[end]
        let span     = Double(end - (i - 1))
        for k in i..<end {
            let t = Double(k - (i - 1)) / span
            result[k] = startVal + t * (endVal - startVal)
        }
        i = end + 1
    }
    return result
}

// MARK: - Fullscreen map with integrated scrubbing

private struct FullscreenRouteView: View {
    let track: [RoutePoint]
    let peakEvents: [PeakEvent]
    var rawFwd: [Float] = []
    var rawLat: [Float] = []

    @State private var scrubFraction: Double? = nil

    private var speeds: [Double] { track.map { $0.speedMps * 3.6 } }
    private var alts: [Double] { smoothElevationGlitches(track.map { $0.altitudeM }) }
    private var hasElevation: Bool { alts.contains(where: { $0 != 0 }) }

    private var scrubCoordinate: CLLocationCoordinate2D? {
        guard let frac = scrubFraction, track.count >= 2 else { return nil }
        let idx = min(track.count - 1, max(0, Int(frac * Double(track.count))))
        return track[idx].coordinate
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteMapView(
                track: track,
                peakEvents: peakEvents,
                scrubCoordinate: scrubCoordinate,
                onScrubFractionChanged: { scrubFraction = $0 }
            )

            VStack(alignment: .leading, spacing: 6) {
                // Speed chart
                if !speeds.isEmpty {
                    HStack {
                        Text("Speed").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        if let frac = scrubFraction {
                            let sIdx = min(speeds.count - 1, max(0, Int(frac * Double(speeds.count))))
                            Text(String(format: "%.0f km/h", speeds[sIdx]))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    ScrubSpeedChart(data: speeds, color: .accentColor, showFill: true,
                                    height: 40, scrubFraction: $scrubFraction)
                }

                // Elevation chart
                if hasElevation {
                    HStack {
                        Text("Elevation").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        if let frac = scrubFraction {
                            let eIdx = min(alts.count - 1, max(0, Int(frac * Double(alts.count))))
                            Text(String(format: "%.0f m", alts[eIdx]))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                    ScrubSpeedChart(data: alts, color: .green, showFill: true,
                                    height: 32, zeroBased: false, scrubFraction: $scrubFraction)
                }

                // G-force readout — appears only while scrubbing
                if let frac = scrubFraction, !rawFwd.isEmpty, rawFwd.count == rawLat.count {
                    let rIdx = min(rawFwd.count - 1, max(0, Int(frac * Double(rawFwd.count))))
                    HStack(spacing: 6) {
                        Text(String(format: "%+.2f g", Double(rawFwd[rIdx]))).foregroundStyle(.blue)
                        Text("fwd").foregroundStyle(.tertiary)
                        Text("·").foregroundStyle(.quaternary)
                        Text(String(format: "%+.2f g", Double(rawLat[rIdx]))).foregroundStyle(.orange)
                        Text("lat").foregroundStyle(.tertiary)
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Interactive scrub speed chart

private struct ScrubSpeedChart: View {
    let data: [Double]
    var color: Color = .accentColor
    var showFill: Bool = true
    var height: CGFloat = 56
    /// When true (default), y axis starts at 0 — correct for speed.
    /// When false, domain is computed from the data range — correct for elevation.
    var zeroBased: Bool = true
    @Binding var scrubFraction: Double?

    private var decimated: [(index: Int, value: Double)] {
        guard !data.isEmpty else { return [] }
        let step = max(1, data.count / 300)
        return Swift.stride(from: 0, to: data.count, by: step).map { (index: $0, value: data[$0]) }
    }

    private var yDomain: ClosedRange<Double> {
        if zeroBased {
            return 0 ... max((data.max() ?? 10) * 1.1, 10)
        }
        let mn = data.min() ?? 0
        let mx = data.max() ?? 10
        let pad = max((mx - mn) * 0.15, 5)
        return (mn - pad) ... (mx + pad)
    }

    private var xMax: Int { max(1, data.count - 1) }

    private var scrubDataIndex: Int? {
        guard let frac = scrubFraction else { return nil }
        return min(xMax, max(0, Int(frac * Double(xMax))))
    }

    var body: some View {
        Chart {
            ForEach(decimated, id: \.index) { point in
                if showFill {
                    AreaMark(x: .value("i", point.index), y: .value("v", point.value))
                        .foregroundStyle(color.opacity(0.12))
                }
                LineMark(x: .value("i", point.index), y: .value("v", point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            if let sx = scrubDataIndex {
                RuleMark(x: .value("scrub", sx))
                    .foregroundStyle(Color(.label).opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0...xMax)
        .frame(height: height)
        .chartOverlay { _ in
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                scrubFraction = max(0, min(1, drag.location.x / geo.size.width))
                            }
                            .onEnded { _ in
                                scrubFraction = nil
                            }
                    )
            }
        }
    }
}
