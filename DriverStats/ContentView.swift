//
//  ContentView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 7/6/26.
//

import Combine
import CoreLocation
import SwiftData
import SwiftUI

struct ContentView: View {
    @StateObject private var motion = MotionManager()
    @StateObject private var location = LocationManager()
    @State private var isTracking = false

    var body: some View {
        TabView {
            NavigationStack {
                if isTracking {
                    TrackingView(motion: motion, location: location, isTracking: $isTracking)
                } else {
                    ReadinessView(motion: motion, location: location, isTracking: $isTracking)
                }
            }
            .tabItem { Label("Record", systemImage: "gauge.with.dots.needle.67percent") }

            NavigationStack {
                SensorsView(motion: motion)
            }
            .tabItem { Label("Live", systemImage: "waveform.path") }

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            NavigationStack {
                SettingsView(motion: motion)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.accentColor)
        .onAppear {
            location.requestPermissionAndStart()
        }
        .onChange(of: location.lastUpdate) { _, _ in
            motion.updateFromGPS(
                course: location.course,
                speedMps: location.speed,
                accuracyM: location.horizontalAccuracy,
                coordinate: location.coordinate
            )
        }
    }
}

#Preview {
    ContentView()
}
