import AVFoundation

@MainActor
final class AudioService {
    private let engine = AVAudioEngine()

    func start() throws {
        guard !engine.isRunning else {
            return
        }

        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}

