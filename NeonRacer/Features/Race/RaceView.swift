import SpriteKit
import SwiftUI

struct RaceView: View {
    let exitRace: () -> Void

    @State private var scene = RaceScene()

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            Button(action: exitRace) {
                Label("Exit race", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.title2.bold())
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.55))
            .padding()
            .accessibilityHint("Returns to the main menu")
        }
        .onAppear {
            scene.scaleMode = .aspectFill
        }
    }
}

#Preview {
    RaceView {}
}

