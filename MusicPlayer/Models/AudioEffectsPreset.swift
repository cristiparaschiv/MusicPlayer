import Foundation

struct AudioEffectsPreset: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let isBuiltIn: Bool

    // EQ
    let eqEnabled: Bool
    let eqGains: [Float]
    let eqPresetId: String?

    // Reverb
    let reverbEnabled: Bool
    let reverbPresetIndex: Int
    let reverbWetDryMix: Float

    // Delay
    let delayEnabled: Bool
    let delayTime: Double
    let delayFeedback: Float
    let delayWetDryMix: Float
    let delayLowPassCutoff: Float

    // Pitch/Speed
    let pitchSpeedEnabled: Bool
    let pitch: Float
    let rate: Float

    static func captureCurrentState(id: String, name: String, isBuiltIn: Bool = false) -> AudioEffectsPreset {
        let eq = EQManager.shared
        let reverb = ReverbManager.shared
        let delay = DelayManager.shared
        let ps = PitchSpeedManager.shared

        return AudioEffectsPreset(
            id: id, name: name, isBuiltIn: isBuiltIn,
            eqEnabled: eq.isEnabled, eqGains: eq.gains, eqPresetId: eq.selectedPreset?.id,
            reverbEnabled: reverb.isEnabled, reverbPresetIndex: reverb.presetIndex, reverbWetDryMix: reverb.wetDryMix,
            delayEnabled: delay.isEnabled, delayTime: delay.delayTime, delayFeedback: delay.feedback,
            delayWetDryMix: delay.wetDryMix, delayLowPassCutoff: delay.lowPassCutoff,
            pitchSpeedEnabled: ps.isEnabled, pitch: ps.pitch, rate: ps.rate
        )
    }

    func apply() {
        let eq = EQManager.shared
        eq.isEnabled = eqEnabled
        eq.gains = eqGains
        if let pid = eqPresetId, let preset = eq.allPresets.first(where: { $0.id == pid }) {
            eq.selectedPreset = preset
        } else {
            eq.selectedPreset = nil
        }

        let reverb = ReverbManager.shared
        reverb.isEnabled = reverbEnabled
        reverb.presetIndex = reverbPresetIndex
        reverb.wetDryMix = reverbWetDryMix

        let delay = DelayManager.shared
        delay.isEnabled = delayEnabled
        delay.delayTime = delayTime
        delay.feedback = delayFeedback
        delay.wetDryMix = delayWetDryMix
        delay.lowPassCutoff = delayLowPassCutoff

        let ps = PitchSpeedManager.shared
        ps.isEnabled = pitchSpeedEnabled
        ps.pitch = pitch
        ps.rate = rate
    }

    // MARK: - Built-in Combined Presets

    static let builtIn: [AudioEffectsPreset] = [
        AudioEffectsPreset(
            id: "slowed_reverb", name: "Slowed + Reverb", isBuiltIn: true,
            eqEnabled: false, eqGains: Array(repeating: 0, count: 10), eqPresetId: "flat",
            reverbEnabled: true, reverbPresetIndex: 4, reverbWetDryMix: 40,
            delayEnabled: false, delayTime: 0.5, delayFeedback: 50, delayWetDryMix: 20, delayLowPassCutoff: 15000,
            pitchSpeedEnabled: true, pitch: -200, rate: 0.85
        ),
        AudioEffectsPreset(
            id: "concert_hall", name: "Concert Hall", isBuiltIn: true,
            eqEnabled: true, eqGains: [5, 4, 3, 2, -1, -1, 0, 2, 3, 4], eqPresetId: "classical",
            reverbEnabled: true, reverbPresetIndex: 4, reverbWetDryMix: 35,
            delayEnabled: false, delayTime: 0.5, delayFeedback: 50, delayWetDryMix: 20, delayLowPassCutoff: 15000,
            pitchSpeedEnabled: false, pitch: 0, rate: 1.0
        ),
        AudioEffectsPreset(
            id: "bathroom", name: "Bathroom Singer", isBuiltIn: true,
            eqEnabled: true, eqGains: [-2, -1, 0, 2, 5, 5, 3, 1, 0, -1], eqPresetId: "vocal_boost",
            reverbEnabled: true, reverbPresetIndex: 0, reverbWetDryMix: 50,
            delayEnabled: true, delayTime: 0.08, delayFeedback: 20, delayWetDryMix: 15, delayLowPassCutoff: 8000,
            pitchSpeedEnabled: false, pitch: 0, rate: 1.0
        ),
        AudioEffectsPreset(
            id: "nightcore", name: "Nightcore", isBuiltIn: true,
            eqEnabled: false, eqGains: Array(repeating: 0, count: 10), eqPresetId: "flat",
            reverbEnabled: false, reverbPresetIndex: 0, reverbWetDryMix: 25,
            delayEnabled: false, delayTime: 0.5, delayFeedback: 50, delayWetDryMix: 20, delayLowPassCutoff: 15000,
            pitchSpeedEnabled: true, pitch: 400, rate: 1.25
        ),
        AudioEffectsPreset(
            id: "practice_slow", name: "Practice (Slow)", isBuiltIn: true,
            eqEnabled: false, eqGains: Array(repeating: 0, count: 10), eqPresetId: "flat",
            reverbEnabled: false, reverbPresetIndex: 0, reverbWetDryMix: 25,
            delayEnabled: false, delayTime: 0.5, delayFeedback: 50, delayWetDryMix: 20, delayLowPassCutoff: 15000,
            pitchSpeedEnabled: true, pitch: 0, rate: 0.75
        ),
        AudioEffectsPreset(
            id: "echo_chamber", name: "Echo Chamber", isBuiltIn: true,
            eqEnabled: false, eqGains: Array(repeating: 0, count: 10), eqPresetId: "flat",
            reverbEnabled: true, reverbPresetIndex: 8, reverbWetDryMix: 30,
            delayEnabled: true, delayTime: 0.4, delayFeedback: 60, delayWetDryMix: 35, delayLowPassCutoff: 12000,
            pitchSpeedEnabled: false, pitch: 0, rate: 1.0
        ),
    ]
}
