import SwiftUI

struct GarageView: View {
    @Binding var profile: PlayerProfile
    @ObservedObject var inputService: InputService
    let saveProfile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedItem: GarageFocus?
    @State private var isShowingCustomization = false

    private enum GarageFocus: Hashable {
        case vehicle(String)
        case customize
        case done
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isCompactHeight = geometry.size.height < 450
                VStack(spacing: isCompactHeight ? 10 : 16) {
                    vehicleCardsRow(isCompactHeight: isCompactHeight)
                    overviewActionsRow
                }
                .padding(.horizontal, isCompactHeight ? 12 : 20)
                .padding(.vertical, isCompactHeight ? 8 : 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(red: 0.02, green: 0.01, blue: 0.08).ignoresSafeArea())
            .navigationTitle("Garage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.bold().monospaced())
                        .focused($focusedItem, equals: .done)
                }
            }
            .sheet(isPresented: $isShowingCustomization) {
                GarageCustomizationView(
                    profile: $profile,
                    inputService: inputService,
                    saveProfile: saveProfile
                )
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            focusedItem = .vehicle(profile.selectedVehicleID)
            configureOverviewInput()
        }
        .onChange(of: isShowingCustomization) { _, isShowing in
            if !isShowing {
                configureOverviewInput()
                focusedItem = .vehicle(profile.selectedVehicleID)
            }
        }
    }

    private func vehicleCardsRow(isCompactHeight: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(ProgressionCatalog.vehicles) { vehicle in
                let unlocked = profile.unlockedVehicleIDs.contains(vehicle.id)
                let selected = profile.selectedVehicleID == vehicle.id

                VehicleComparisonCard(
                    vehicle: vehicle,
                    palette: ProgressionCatalog.palette(id: profile.selectedPaletteID),
                    unlocked: unlocked,
                    selected: selected,
                    compactHeight: isCompactHeight
                ) {
                    profile.selectedVehicleID = vehicle.id
                    saveProfile()
                }
                .focused($focusedItem, equals: .vehicle(vehicle.id))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewActionsRow: some View {
        let selectedVehicle = ProgressionCatalog.vehicle(id: profile.selectedVehicleID)
        let selectedPalette = ProgressionCatalog.palette(id: profile.selectedPaletteID)
        let selectedRoute = ProgressionCatalog.routes.first { $0.id == profile.selectedRouteID }

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SELECTED LOADOUT")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)
                Text("\(selectedVehicle.displayName.uppercased()) • \(selectedPalette.displayName) • \(selectedRoute?.displayName ?? "Route")")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                isShowingCustomization = true
            } label: {
                Label("MODIFY SELECTED CAR", systemImage: "slider.horizontal.3")
                    .font(.caption.bold().monospaced())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .focused($focusedItem, equals: .customize)
            .accessibilityHint("Opens palette, route, and records customization screen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var overviewFocusOrder: [GarageFocus] {
        ProgressionCatalog.vehicles
            .filter { profile.unlockedVehicleIDs.contains($0.id) }
            .map { GarageFocus.vehicle($0.id) }
            + [.customize, .done]
    }

    private func configureOverviewInput() {
        inputService.actionHandler = handleOverviewAction
    }

    private func handleOverviewAction(_ action: PlayerAction) {
        switch action {
        case .steerLeft, .menuLeft, .menuUp:
            moveOverviewFocus(-1)
        case .steerRight, .menuRight, .menuDown:
            moveOverviewFocus(1)
        case .confirm:
            confirmOverviewItem()
        case .cancel, .pause:
            dismiss()
        default:
            break
        }
    }

    private func moveOverviewFocus(_ offset: Int) {
        let order = overviewFocusOrder
        let current = focusedItem.flatMap(order.firstIndex) ?? 0
        focusedItem = order[(current + offset + order.count) % order.count]
    }

    private func confirmOverviewItem() {
        guard let focusedItem else { return }
        switch focusedItem {
        case .vehicle(let id):
            profile.selectedVehicleID = id
            saveProfile()
        case .customize:
            isShowingCustomization = true
        case .done:
            dismiss()
        }
    }
}

private struct VehicleComparisonCard: View {
    let vehicle: VehicleDefinition
    let palette: GaragePaletteDefinition
    let unlocked: Bool
    let selected: Bool
    let compactHeight: Bool
    let selectAction: () -> Void

    var body: some View {
        Button(action: selectAction) {
            VStack(alignment: .leading, spacing: 8) {
                cardHeader
                carPreview
                availabilityText
                CompactStatGrid(configuration: vehicle.configuration)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                selected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.cyan : Color.white.opacity(0.10), lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(unlocked ? "Selects \(vehicle.displayName)" : vehicle.unlockRequirement.description)
    }

    private var cardHeader: some View {
        HStack(alignment: .center) {
            Image(systemName: selectionIconName)
                .font(.caption.bold())
                .foregroundStyle(selectionIconColor)
            Text(vehicle.displayName.uppercased())
                .font(.caption.bold().monospaced())
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var carPreview: some View {
        CarPreview(vehicle: vehicle, palette: palette)
            .frame(height: compactHeight ? 52 : 78)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var availabilityText: some View {
        Text(unlocked ? vehicle.tagline : vehicle.unlockRequirement.description)
            .font(.caption2)
            .foregroundStyle(unlocked ? Color.secondary : Color.orange)
            .lineLimit(2)
            .frame(height: 26, alignment: .topLeading)
    }

    private var selectionIconName: String {
        guard unlocked else { return "lock.fill" }
        return selected ? "checkmark.circle.fill" : "circle"
    }

    private var selectionIconColor: Color {
        guard unlocked else { return .orange }
        return selected ? .cyan : .secondary
    }

    private var accessibilitySummary: String {
        let state = unlocked ? (selected ? "selected" : "unlocked") : "locked"
        let configuration = vehicle.configuration
        return "\(vehicle.displayName), \(state), "
            + "top speed \(Int(configuration.maximumSpeed)), "
            + "acceleration \(Int(configuration.acceleration)), "
            + "handling \(configuration.steeringRate.formatted()), "
            + "boost \(configuration.boost.capacity.formatted()) seconds"
    }
}

private struct CompactStatGrid: View {
    let configuration: RaceConfiguration

    var body: some View {
        VStack(spacing: 4) {
            compactRow("SPD", configuration.maximumSpeed, maximum: 128)
            compactRow("ACC", configuration.acceleration, maximum: 44)
            compactRow("HND", configuration.steeringRate, maximum: 2)
            compactRow("BST", configuration.boost.capacity, maximum: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Top speed \(Int(configuration.maximumSpeed)), "
                + "acceleration \(Int(configuration.acceleration)), "
                + "handling \(configuration.steeringRate.formatted()), "
                + "boost capacity \(configuration.boost.capacity.formatted()) seconds"
        )
    }

    private func compactRow(_ title: String, _ value: Double, maximum: Double) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            ProgressView(value: value, total: maximum)
                .tint(.cyan)
            Text(value.formatted(.number.precision(.fractionLength(0...1))))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct GarageCustomizationView: View {
    @Binding var profile: PlayerProfile
    @ObservedObject var inputService: InputService
    let saveProfile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedItem: CustomizationFocus?

    private enum CustomizationFocus: Hashable {
        case palette(String)
        case route(String)
        case done
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    activeVehicleHeader
                    paletteSection
                    routeSection
                    recordsSection
                }
                .padding()
            }
            .background(Color(red: 0.02, green: 0.01, blue: 0.08).ignoresSafeArea())
            .navigationTitle("Modifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.bold().monospaced())
                        .focused($focusedItem, equals: .done)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            focusedItem = .palette(profile.selectedPaletteID)
            inputService.actionHandler = handleCustomizationAction
        }
    }

    private var activeVehicleHeader: some View {
        let vehicle = ProgressionCatalog.vehicle(id: profile.selectedVehicleID)
        let palette = ProgressionCatalog.palette(id: profile.selectedPaletteID)

        return HStack(spacing: 16) {
            CarPreview(vehicle: vehicle, palette: palette)
                .frame(width: 140, height: 86)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("TUNING CHASSIS")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.cyan)
                Text(vehicle.displayName.uppercased())
                    .font(.headline.bold().monospaced())
                Text(vehicle.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var paletteSection: some View {
        selectionSection(title: "PALETTE & NEON TRIM") {
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
        selectionSection(title: "RACE ROUTE") {
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
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func selectionSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .padding(12)
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

    private var customizationFocusOrder: [CustomizationFocus] {
        ProgressionCatalog.palettes
            .filter { profile.unlockedPaletteIDs.contains($0.id) }
            .map { CustomizationFocus.palette($0.id) }
            + ProgressionCatalog.routes
            .filter { profile.unlockedRouteIDs.contains($0.id) }
            .map { CustomizationFocus.route($0.id) }
            + [.done]
    }

    private func handleCustomizationAction(_ action: PlayerAction) {
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
        let order = customizationFocusOrder
        let current = focusedItem.flatMap(order.firstIndex) ?? 0
        focusedItem = order[(current + offset + order.count) % order.count]
    }

    private func confirmFocusedItem() {
        guard let focusedItem else { return }
        switch focusedItem {
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
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                    .shadow(color: Color(hex: palette.primaryHex), radius: 10)
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
