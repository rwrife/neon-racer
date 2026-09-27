import SwiftUI

struct TouchDrivingControls: View {
    let inputMethod: DrivingInputMethod
    let setSteering: (Double) -> Void
    let setAction: (PlayerAction, Bool) -> Void

    @State private var steeringValue = 0.0

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom) {
                steeringSurface
                    .frame(
                        width: min(max(proxy.size.width * 0.34, 220), 340),
                        height: 86
                    )
                Spacer(minLength: 24)
                HStack(alignment: .bottom, spacing: 10) {
                    DrivingHoldButton(title: "BRAKE", systemImage: "stop.fill") { pressed in
                        setAction(.brake, pressed)
                    }

                    DrivingHoldButton(title: "BOOST", systemImage: "bolt.fill", tint: .cyan) { pressed in
                        setAction(.boost, pressed)
                    }
                    DrivingHoldButton(title: "GO", systemImage: "arrow.up", tint: .pink) { pressed in
                        setAction(.throttle, pressed)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(inputMethod == .controller ? 0.35 : 1)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var steeringSurface: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(.black.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(.cyan.opacity(0.48), lineWidth: 1.2)
                    )
                HStack(spacing: 0) {
                    steeringZoneLabel(systemImage: "chevron.left.2", isActive: steeringValue < -0.08)
                    Rectangle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 1)
                    steeringZoneLabel(systemImage: "chevron.right.2", isActive: steeringValue > 0.08)
                }
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 14, height: 14)
                    .overlay { Circle().stroke(.cyan.opacity(0.7), lineWidth: 1) }
                    .offset(x: steeringValue * (width / 2 - 24))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = (value.location.x / width) * 2 - 1
                        steeringValue = min(max(normalized, -1), 1)
                        setSteering(steeringValue)
                    }
                    .onEnded { _ in
                        steeringValue = 0
                        setSteering(0)
                    }
            )
            .accessibilityLabel("Steering")
            .accessibilityHint("Drag or hold the left and right steering zones")
            .accessibilityValue(steeringValue < -0.1 ? "Left" : steeringValue > 0.1 ? "Right" : "Centered")
        }
    }

    private func steeringZoneLabel(systemImage: String, isActive: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(isActive ? .cyan.opacity(0.16) : .clear)
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(isActive ? .cyan : .white.opacity(0.58))
        }
    }
}

private struct DrivingHoldButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .orange
    let changed: (Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.title3.bold())
            Text(title)
                .font(.caption2.bold().monospaced())
        }
        .foregroundStyle(.white.opacity(isPressed ? 0.95 : 0.76))
        .frame(width: 72, height: 72)
        .background(
            Circle()
                .fill(isPressed ? tint.opacity(0.55) : .black.opacity(0.22))
                .overlay(Circle().stroke(tint.opacity(isPressed ? 0.95 : 0.52), lineWidth: 1.2))
        )
        .scaleEffect(isPressed ? 1.04 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in setPressed(true) }
                .onEnded { _ in setPressed(false) }
        )
        .accessibilityLabel(title)
        .accessibilityHint("Hold to \(title.lowercased())")
        .accessibilityAddTraits(isPressed ? [.isButton, .isSelected] : .isButton)
    }

    private func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed
        changed(pressed)
    }
}

private extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
