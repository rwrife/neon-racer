import SwiftUI

struct RootView: View {
    private enum Destination {
        case menu
        case race
    }

    @State private var destination = Destination.menu

    var body: some View {
        Group {
            switch destination {
            case .menu:
                MainMenuView {
                    destination = .race
                }
            case .race:
                RaceView {
                    destination = .menu
                }
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }
}

#Preview {
    RootView()
}

