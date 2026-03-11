import Foundation

struct EQPreset: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let gains: [Float]  // 10 values, -12.0 to +12.0 dB
    let isBuiltIn: Bool

    static let bandCount = 10
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandLabels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let minGain: Float = -12.0
    static let maxGain: Float = 12.0

    static let builtIn: [EQPreset] = [
        EQPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], isBuiltIn: true),
        EQPreset(id: "bass_boost", name: "Bass Boost", gains: [8, 6, 4, 2, 0, 0, 0, 0, 0, 0], isBuiltIn: true),
        EQPreset(id: "bass_reducer", name: "Bass Reducer", gains: [-8, -6, -4, -2, 0, 0, 0, 0, 0, 0], isBuiltIn: true),
        EQPreset(id: "treble_boost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 0, 2, 4, 6, 8], isBuiltIn: true),
        EQPreset(id: "treble_reducer", name: "Treble Reducer", gains: [0, 0, 0, 0, 0, 0, -2, -4, -6, -8], isBuiltIn: true),
        EQPreset(id: "rock", name: "Rock", gains: [5, 3, -1, -3, -1, 2, 4, 5, 5, 4], isBuiltIn: true),
        EQPreset(id: "pop", name: "Pop", gains: [-2, -1, 0, 2, 4, 4, 2, 0, -1, -2], isBuiltIn: true),
        EQPreset(id: "jazz", name: "Jazz", gains: [4, 3, 1, 2, -2, -2, 0, 1, 3, 4], isBuiltIn: true),
        EQPreset(id: "classical", name: "Classical", gains: [5, 4, 3, 2, -1, -1, 0, 2, 3, 4], isBuiltIn: true),
        EQPreset(id: "electronic", name: "Electronic", gains: [5, 4, 1, 0, -2, 2, 1, 3, 4, 5], isBuiltIn: true),
        EQPreset(id: "hip_hop", name: "Hip Hop", gains: [6, 5, 3, 1, -1, -1, 1, 0, 2, 3], isBuiltIn: true),
        EQPreset(id: "acoustic", name: "Acoustic", gains: [4, 3, 1, 0, 1, 1, 2, 3, 3, 2], isBuiltIn: true),
        EQPreset(id: "vocal_boost", name: "Vocal Boost", gains: [-2, -1, 0, 2, 5, 5, 3, 1, 0, -1], isBuiltIn: true),
        EQPreset(id: "loudness", name: "Loudness", gains: [6, 4, 0, 0, -2, 0, -1, -5, 5, 1], isBuiltIn: true),
    ]

    static let flat = builtIn[0]
}
