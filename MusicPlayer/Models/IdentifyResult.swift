import Foundation

struct IdentifyResult: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let trackNumber: Int?
    let discNumber: Int?
    let year: String
    let genre: String
    let confidence: Double
}
