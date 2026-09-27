import SwiftUI

struct GarageView: View {
    @Binding var profile: PlayerProfile
    @ObservedObject var inputService: InputService
    let saveProfile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedItem: GarageFocus?

    private enum GarageFocus: Hashable {
        case vehicle(String)
        case palette(String)
        case route(String)
        case done
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    selectedVehiclePreview
                    vehicleSection
                    paletteSection
                    routeSection
                    recordsSection
                }
                .padding()
            }
            .background(Color(red: 0.02, green: 0.01, blue: 0.08).ignoresSafeArea())
            .navigationTitle("Garage")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .focused($focusedItem, equals: .done)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            focusedItem = .vehicle(profile.selectedVehicleID)
            inputService.actionHandler = handleInputAction
        }
    }

    private var selectedVehiclePreview: some View {
        let vehicle = ProgressionCatalog.vehicle(id: profile.selectedVehicleID)
        let palette = ProgressionCatalog.palette(id: profile.selectedPaletteID)

        return VStack(spacing: 16) {
            CarPreview(vehicle: vehicle, palette: palette)
                .frame(height: 190)
                .accessibilityHidden(true)
            Text(vehicle.displayName.uppercased())
                .font(.title2.bold().monospaced())
            Text(vehicle.tagline)
                .foregroundStyle(.secondary)
            StatGrid(configuration: vehicle.configuration)
        }
        .padding(20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }

    private var vehicleSection: some View {
        selectionSection(title: "CHASSIS") {
            ForEach(ProgressionCatalog.vehicles) { vehicle in
                selectionButton(
                    title: vehicle.displayName,
                    subtitle: vehicle.tagline,
                    requirement: vehicle.unlockRequirement,
                    unlocked: profile.unlockedVehicleIDs.contains(vehicle.id),
                    selected: profile.selectedVehicleID == vehicle.id
                ) {
                    profile.selectedVehicleID = vehicle.id
                    saveProfile()
                }
                .focused($focusedItem, equals: .vehicle(vehicle.id))
            }
        }
    }

    private var paletteSection: some View {
        selectionSection(title: "PALETTE") {
            ForEach(ProgressionCatalog.palettes) { palette in
                selectionButton(
                    title: palette.displayName,
                    subtitle: palette.unlockRequirement.description,
                    requirement: palette.unlockRequirement,
                    unlocked: profile.unlockedPaletteIDs.contains(palette.id),
                    selected: profile.selectedPaletteID == palette.id
                ) {
                    profile.selectedPaletteID = palette.id
                    saveProfile()
                }
                .focused($focusedItem, equals: .palette(palette.id))
            }
        }
    }

    private var routeSection: some View {
        selectionSection(title: "ROUTE") {
            ForEach(ProgressionCatalog.routes) { route in
                selectionButton(
                    title: route.displayName,
                    subtitle: route.subtitle,
                    requirement: route.unlockRequirement,
                    unlocked: profile.unlockedRouteIDs.contains(route.id),
                    selected: profile.selectedRouteID == route.id
                ) {
                    profile.selectedRouteID = route.id
                    saveProfile()
                }
                .focused($focusedItem, equals: .route(route.id))
            }
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECORDS")
                .font(.headline.monospaced())
            ForEach(ProgressionCatalog.routes) { route in
                let record = profile.recordsByRoute[route.id]
                HStack {
                    Text(route.displayName)
                    Spacer()
                    Text(recordText(record))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }

    private func selectionSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.monospaced())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionButton(
        title: String,
        subtitle: String,
        requirement: UnlockRequirement,
        unlocked: Bool,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: unlocked ? (selected ? "checkmark.circle.fill" : "circle") : "lock.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.bold())
                    Text(unlocked ? subtitle : requirement.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(
                selected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityHint(unlocked ? "Selects \(title)" : requirement.description)
    }

    private func recordText(_ record: RouteRecord?) -> String {
        guard let record else { return "No finish yet" }
        let time = record.bestTime.map { String(format: "%.2fs", $0) } ?? "—"
        return "\(record.bestScore.formatted()) pts • \(time)"
    }

    private var focusOrder: [GarageFocus] {
        ProgressionCatalog.vehicles
            .filter { profile.unlockedVehicleIDs.contains($0.id) }
            .map { GarageFocus.vehicle($0.id) }
            + ProgressionCatalog.palettes
            .filter { profile.unlockedPaletteIDs.contains($0.id) }
            .map { GarageFocus.palette($0.id) }
            + ProgressionCatalog.routes
            .filter { profile.unlockedRouteIDs.contains($0.id) }
            .map { GarageFocus.route($0.id) }
            + [.done]
    }

    private func handleInputAction(_ action: PlayerAction) {
        switch action {
        case .menuUp:
            moveFocus(-1)
        case .menuDown:
            moveFocus(1)
        case .confirm:
            confirmFocusedItem()
        case .cancel, .pause:
            dismiss()
        default:
            break
        }
    }

    private func moveFocus(_ offset: Int) {
        let order = focusOrder
        let current = focusedItem.flatMap(order.firstIndex) ?? 0
        focusedItem = order[(current + offset + order.count) % order.count]
    }

    private func confirmFocusedItem() {
        guard let focusedItem else {
            return
        }
        switch focusedItem {
        case .vehicle(let id):
            profile.selectedVehicleID = id
            saveProfile()
        case .palette(let id):
            profile.selectedPaletteID = id
            saveProfile()
        case .route(let id):
            profile.selectedRouteID = id
            saveProfile()
        case .done:
            dismiss()
        }
    }
}

private struct StatGrid: View {
    let configuration: RaceConfiguration

    var body: some View {
        Grid(horizontalSpacing: 18, verticalSpacing: 8) {
            stat("TOP SPEED", configuration.maximumSpeed, maximum: 128)
            stat("ACCELERATION", configuration.acceleration, maximum: 44)
            stat("HANDLING", configuration.steeringRate, maximum: 2)
            stat("BOOST", configuration.boost.capacity, maximum: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Top speed \(Int(configuration.maximumSpeed)), "
                + "acceleration \(Int(configuration.acceleration)), "
                + "handling \(configuration.steeringRate.formatted()), "
                + "boost capacity \(configuration.boost.capacity.formatted()) seconds"
        )
    }

    private func stat(_ title: String, _ value: Double, maximum: Double) -> some View {
        GridRow {
            Text(title)
                .font(.caption2.bold().monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView(value: value, total: maximum)
                .tint(.cyan)
            Text(value.formatted(.number.precision(.fractionLength(0...1))))
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct CarPreview: View {
    let vehicle: VehicleDefinition
    let palette: GaragePaletteDefinition

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                ForEach(0..<7, id: \.self) { index in
                    Path { path in
                        let y = proxy.size.height * (0.58 + CGFloat(index) * 0.07)
                        path.move(to: CGPoint(x: width * 0.5, y: proxy.size.height * 0.48))
                        path.addLine(to: CGPoint(x: index.isMultiple(of: 2) ? 0 : width, y: y))
                    }
                    .stroke(Color(hex: palette.secondaryHex).opacity(0.25), lineWidth: 1)
                }

                CarSilhouette(profile: vehicle.configurationProfile)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: palette.primaryHex), Color(hex: palette.secondaryHex)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    CarSilhouette(profile: vehicle.configurationProfile)
                        .stroke(Color.white.opacity(0.8), lineWidth: 3)
                )
                .shadow(color: Color(hex: palette.primaryHex), radius: 18)
            }
        }
    }
}

private struct CarSilhouette: Shape {
    let profile: DifficultyProfile

    func path(in rect: CGRect) -> Path {
        let proportions: (shoulder: CGFloat, canopy: CGFloat) = switch profile {
        case .novice: (0.29, 0.40)
        case .standard: (0.32, 0.43)
        case .expert: (0.35, 0.46)
        }
        return Path { path in
            path.move(to: CGPoint(x: rect.width * 0.23, y: rect.height * 0.78))
            path.addLine(to: CGPoint(x: rect.width * proportions.shoulder, y: rect.height * 0.34))
            path.addLine(to: CGPoint(x: rect.width * proportions.canopy, y: rect.height * 0.19))
            path.addLine(
                to: CGPoint(x: rect.width * (1 - proportions.canopy), y: rect.height * 0.19)
            )
            path.addLine(
                to: CGPoint(x: rect.width * (1 - proportions.shoulder), y: rect.height * 0.34)
            )
            path.addLine(to: CGPoint(x: rect.width * 0.77, y: rect.height * 0.78))
            path.closeSubpath()
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
