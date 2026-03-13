import Foundation

struct RadioStation: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let priority: Int         // higher = more specific; tracks matching multiple stations go to the highest priority one
    let keywords: [String]    // genre keywords for fuzzy matching (lowercase)

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RadioStation, rhs: RadioStation) -> Bool {
        lhs.id == rhs.id
    }

    /// Returns keywords from all stations that have higher priority than this one.
    /// Used to exclude tracks that belong to a more specific station.
    var excludedKeywords: [String] {
        RadioStation.allStations
            .filter { $0.priority > self.priority && $0.id != self.id }
            .flatMap { $0.keywords }
    }
}

// MARK: - Predefined Stations
//
// Priority guide:
//   1 = broad umbrella genres (Rock, Pop, Indie) — these defer to more specific stations
//   2 = mid-specificity (Electronic, Hip-Hop, Country, Folk, R&B)
//   3 = high specificity (Metal, Punk, Blues, Jazz, Classical, Reggae, Latin)
//
// Example: a track tagged "Death Metal" matches both Rock ("rock" in "death metal rock") and Metal.
// Since Metal has priority 3 > Rock's priority 1, Rock Radio excludes it.

extension RadioStation {
    static let allStations: [RadioStation] = [
        // Priority 1 — Broad
        RadioStation(id: "rock", name: "Rock Radio", icon: "guitars.fill", priority: 1,
                     keywords: ["rock", "hard rock", "classic rock", "progressive rock", "indie rock",
                                "alternative rock", "soft rock", "southern rock", "psychedelic rock",
                                "garage rock", "grunge", "post-punk", "new wave", "stoner rock",
                                "art rock", "glam rock", "krautrock"]),

        RadioStation(id: "pop", name: "Pop Radio", icon: "star.fill", priority: 1,
                     keywords: ["pop", "synth-pop", "synthpop", "dance pop", "electropop",
                                "dream pop", "chamber pop", "art pop", "power pop", "teen pop",
                                "k-pop", "j-pop", "europop", "bubblegum pop"]),

        RadioStation(id: "indie", name: "Indie Radio", icon: "sparkle", priority: 1,
                     keywords: ["indie", "indie rock", "indie pop", "indie folk",
                                "indie electronic", "lo-fi", "lofi", "bedroom pop",
                                "shoegaze", "post-rock", "math rock", "noise pop"]),

        // Priority 2 — Mid-specificity
        RadioStation(id: "electronic", name: "Electronic Radio", icon: "waveform", priority: 2,
                     keywords: ["electronic", "electronica", "edm", "techno", "house", "trance",
                                "ambient", "drum and bass", "dnb", "dubstep", "idm", "downtempo",
                                "trip-hop", "trip hop", "chillout", "deep house", "progressive house",
                                "electro", "synthwave", "retrowave"]),

        RadioStation(id: "hiphop", name: "Hip-Hop Radio", icon: "mic.fill", priority: 2,
                     keywords: ["hip-hop", "hip hop", "hiphop", "rap", "trap", "grime",
                                "boom bap", "conscious rap", "gangsta rap", "old school hip hop",
                                "underground hip hop", "southern hip hop"]),

        RadioStation(id: "country", name: "Country Radio", icon: "leaf.fill", priority: 2,
                     keywords: ["country", "country rock", "alt-country", "alternative country",
                                "americana", "bluegrass", "country pop", "outlaw country",
                                "country folk", "honky tonk", "nashville"]),

        RadioStation(id: "folk", name: "Folk Radio", icon: "tree.fill", priority: 2,
                     keywords: ["folk", "indie folk", "folk rock", "contemporary folk",
                                "traditional folk", "acoustic", "singer-songwriter",
                                "celtic", "world folk"]),

        RadioStation(id: "rnb", name: "R&B Radio", icon: "sparkles", priority: 2,
                     keywords: ["r&b", "rnb", "rhythm and blues", "soul", "neo-soul", "neo soul",
                                "motown", "funk", "contemporary r&b", "new jack swing"]),

        // Priority 3 — Highly specific
        RadioStation(id: "metal", name: "Metal Radio", icon: "bolt.fill", priority: 3,
                     keywords: ["metal", "heavy metal", "thrash metal", "death metal", "black metal",
                                "doom metal", "power metal", "progressive metal", "nu metal", "metalcore",
                                "symphonic metal", "speed metal", "industrial metal", "sludge metal",
                                "stoner metal", "folk metal", "gothic metal", "deathcore",
                                "grindcore", "djent"]),

        RadioStation(id: "punk", name: "Punk Radio", icon: "exclamationmark.triangle.fill", priority: 3,
                     keywords: ["punk", "punk rock", "hardcore", "hardcore punk", "post-hardcore",
                                "pop punk", "ska punk", "emo", "screamo", "crust punk",
                                "anarcho-punk", "street punk"]),

        RadioStation(id: "blues", name: "Blues Radio", icon: "flame.fill", priority: 3,
                     keywords: ["blues", "electric blues", "delta blues", "chicago blues",
                                "country blues", "blues rock", "soul blues"]),

        RadioStation(id: "jazz", name: "Jazz Radio", icon: "pianokeys", priority: 3,
                     keywords: ["jazz", "smooth jazz", "bebop", "cool jazz", "free jazz",
                                "fusion", "jazz fusion", "swing", "big band", "bossa nova",
                                "latin jazz", "acid jazz", "nu jazz", "vocal jazz"]),

        RadioStation(id: "classical", name: "Classical Radio", icon: "music.quarternote.3", priority: 3,
                     keywords: ["classical", "baroque", "romantic", "orchestra", "orchestral",
                                "chamber music", "symphony", "opera", "choral", "contemporary classical",
                                "minimalism", "neoclassical"]),

        RadioStation(id: "reggae", name: "Reggae Radio", icon: "sun.max.fill", priority: 3,
                     keywords: ["reggae", "dancehall", "dub", "ska", "rocksteady",
                                "roots reggae", "ragga", "lovers rock"]),

        RadioStation(id: "latin", name: "Latin Radio", icon: "music.mic", priority: 3,
                     keywords: ["latin", "salsa", "reggaeton", "bachata", "merengue",
                                "cumbia", "latin pop", "latin rock", "bossa nova", "samba",
                                "tango", "flamenco", "mariachi", "tejano"]),
    ]
}
