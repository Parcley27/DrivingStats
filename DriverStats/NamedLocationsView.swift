//
//  NamedLocationsView.swift
//  DriverStats
//
//  Created by Pierce Oxley on 6/27/26.
//

import CoreLocation
import MapKit
import SwiftData
import SwiftUI

// MARK: - Named Locations list

struct NamedLocationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NamedLocation.name) private var locations: [NamedLocation]
    @State private var showingAdd = false
    @State private var editingLocation: NamedLocation?
    /// Names of locations that existed when this screen appeared, so deletions can be detected.
    @State private var knownNamesOnAppear: Set<String> = []

    var body: some View {
        List {
            if locations.isEmpty {
                ContentUnavailableView(
                    "No Named Locations",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Tap + to add places like Home or Work. Drives that start or end nearby will use the name automatically.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(locations) { loc in
                    Button {
                        editingLocation = loc
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc.name)
                                .font(.body)
                                .foregroundStyle(Color(.label))
                            Text(String(format: "%.5f, %.5f · %.0f m radius",
                                        loc.latitude, loc.longitude, loc.radius))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { modelContext.delete(locations[$0]) }
                }
            }
        }
        .navigationTitle("Named Locations")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            if !locations.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NamedLocationFormView(existing: nil)
        }
        .sheet(item: $editingLocation) { loc in
            NamedLocationFormView(existing: loc)
        }
        .onAppear {
            knownNamesOnAppear = Set(locations.map(\.name))
        }
        .onDisappear {
            propagateToAllSessions()
        }
    }

    // MARK: - History propagation

    /// Re-evaluates every stored session against the current named locations:
    /// - Applies a named location name when the session's start/end coordinate falls within radius.
    /// - Clears a name that came from a location that has since been deleted or moved away,
    ///   letting the history card fall back to the date label.
    private func propagateToAllSessions() {
        let descriptor = FetchDescriptor<DriveSession>()
        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        let currentNames = Set(locations.map(\.name))
        // Names that existed before but are now gone (deleted or renamed).
        let removedNames = knownNamesOnAppear.subtracting(currentNames)

        var changed = false
        for session in sessions {
            guard session.routeLatitudes.count >= 2,
                  session.routeLongitudes.count == session.routeLatitudes.count else { continue }

            let startCoord = CLLocationCoordinate2D(
                latitude: session.routeLatitudes[0],
                longitude: session.routeLongitudes[0]
            )
            let endCoord = CLLocationCoordinate2D(
                latitude: session.routeLatitudes[session.routeLatitudes.count - 1],
                longitude: session.routeLongitudes[session.routeLongitudes.count - 1]
            )

            // Apply the most-specific (smallest-radius) matching named location.
            let bestStart = locations.filter { $0.contains(startCoord) }.min(by: { $0.radius < $1.radius })
            if let name = bestStart?.name, session.startPlaceName != name {
                session.startPlaceName = name
                changed = true
            } else if bestStart == nil, let current = session.startPlaceName, removedNames.contains(current) {
                // The name came from a location that no longer exists — clear it.
                session.startPlaceName = nil
                changed = true
            }

            let bestEnd = locations.filter { $0.contains(endCoord) }.min(by: { $0.radius < $1.radius })
            if let name = bestEnd?.name, session.endPlaceName != name {
                session.endPlaceName = name
                changed = true
            } else if bestEnd == nil, let current = session.endPlaceName, removedNames.contains(current) {
                session.endPlaceName = nil
                changed = true
            }
        }

        if changed { try? modelContext.save() }
    }
}

// MARK: - Add / Edit form

struct NamedLocationFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let existing: NamedLocation?

    @State private var name: String = ""
    @State private var radius: Double = 200
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @State private var hasCoordinate = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Home, Work, Track Day", text: $name)
                }

                Section {
                    ZStack(alignment: .center) {
                        Map(position: $cameraPosition) {
                            if hasCoordinate {
                                MapCircle(center: coordinate, radius: radius)
                                    .foregroundStyle(Color.accentColor.opacity(0.15))
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onMapCameraChange(frequency: .continuous) { context in
                            coordinate = context.region.center
                            hasCoordinate = true
                        }

                        // Fixed centre-pin overlay
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                            .allowsHitTesting(false)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("Location - move map to adjust pin")
                } footer: {
                    if hasCoordinate {
                        Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Match radius")
                            Spacer()
                            Text(radius >= 1000
                                 ? String(format: "%.1f km", radius / 1000)
                                 : String(format: "%.0f m", radius))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }
                        Slider(value: $radius, in: 50...2000, step: 50)
                            .tint(.accentColor)
                        HStack {
                            Text("50 m").font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                            Text("2 km").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Drives that start or end within this distance use this name instead of the geocoded neighbourhood.")
                }
            }
            .navigationTitle(existing == nil ? "Add Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !hasCoordinate)
                }
            }
            .task {
                setupInitialState()
            }
        }
    }

    private func setupInitialState() {
        if let loc = existing {
            name = loc.name
            radius = loc.radius
            let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
            coordinate = coord
            hasCoordinate = true
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: max(loc.radius * 8, 800),
                longitudinalMeters: max(loc.radius * 8, 800)
            ))
        } else if let coord = CLLocationManager().location?.coordinate {
            coordinate = coord
            hasCoordinate = true
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            ))
        }
    }

    private func save() {
        guard hasCoordinate else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let loc = existing {
            loc.name = trimmed
            loc.latitude = coordinate.latitude
            loc.longitude = coordinate.longitude
            loc.radius = radius
        } else {
            modelContext.insert(NamedLocation(
                name: trimmed,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radius: radius
            ))
        }
        dismiss()
    }
}
