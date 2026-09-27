# Audio provenance

CyberRun ships `NeonRacer/Resources/CyberpunkSpaceRace.mp3` for the title screen. Its creator and commercial distribution rights need owner verification before submission; see the asset provenance register.

Race music, engine, tire, ambience, UI, impact, boost, checkpoint, finish, and failure sounds are procedurally synthesized in Swift in `NeonRacer/Services/Audio/AudioService.swift` using AVAudioEngine player nodes fed with generated PCM buffers. The race loop uses bass, arpeggio, pad, drum, and countdown pulse stems. Vehicle and environment layers are generated from oscillator/noise code and mixed at runtime.

No third-party sound libraries or sample packs are used by the procedural race audio. The title soundtrack must be cleared separately.
