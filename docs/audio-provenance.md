# Audio provenance

Neon Racer does not ship downloaded, sampled, or licensed audio assets.

All current music, engine, tire, ambience, UI, impact, boost, checkpoint, finish, and failure sounds are procedurally synthesized in Swift in `NeonRacer/Services/Audio/AudioService.swift` using AVAudioEngine player nodes fed with generated PCM buffers. The synthwave music loop is generated from original oscillator/noise code for bass, arpeggio, pad, drum, and countdown pulse stems. Vehicle and environment layers are generated from original oscillator/noise code and mixed at runtime.

No commercial songs, third-party sound libraries, sample packs, streaming audio, or external recordings are used.
