import SwiftUI

struct MainMenuView: View {
    let startRace: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    NeonPalette.midnight,
                    NeonPalette.purple.opacity(0.8),
                    NeonPalette.midnight
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("NEON RACER")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(NeonPalette.cyan)
                    .shadow(color: NeonPalette.cyan.opacity(0.9), radius: 18)
                    .accessibilityAddTraits(.isHeader)

                Text("CHASE THE HORIZON")
                    .font(.headline.monospaced())
                    .tracking(6)
                    .foregroundStyle(NeonPalette.magenta)

                Button(action: startRace) {
                    Text("START ENGINE")
                        .font(.title3.bold().monospaced())
                        .padding(.horizontal, 36)
                        .padding(.vertical, 16)
                        .frame(minWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .tint(NeonPalette.magenta)
                .accessibilityHint("Starts a new race")

                Spacer()

                Text("Native Swift • iOS 26+")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(40)
        }
    }
}

#Preview {
    MainMenuView {}
}

