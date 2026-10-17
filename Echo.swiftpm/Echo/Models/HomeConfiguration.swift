import Foundation

/// Stable identifiers keep a saved Home order intact as new sections become available.
enum HomeSection: String, Codable, CaseIterable, Identifiable {
    case nowPlaying, quickAccess, quickPicks, forYou, recentlyPlayed, artists, recentlyAdded
    case discovery, albums, favorites, podcasts, onlineAlbums
    case hiddenGems, revisitAlbums, listeningWeek, vibe, surprise, flow, timeMachine, upNext
    case playlists, favoriteAlbums

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .nowPlaying: "home_now_playing"
        case .quickAccess: "home_quick_access"
        case .quickPicks: "home_quick_picks"
        case .forYou: "home_for_you"
        case .recentlyPlayed: "homeview_recent_played"
        case .artists: "home_favorite_artists"
        case .recentlyAdded: "homeview_recent_added"
        case .discovery: "home_discovery_title"
        case .albums: "home_local_albums"
        case .favorites: "homeview_favorites"
        case .podcasts: "podcasts_recommended"
        case .onlineAlbums: "home_online_albums"
        case .hiddenGems: "smart_hidden_gems"
        case .revisitAlbums: "smart_revisit"
        case .listeningWeek: "smart_week"
        case .vibe: "smart_vibe"
        case .surprise: "smart_surprise"
        case .flow: "smart_flow"
        case .timeMachine: "smart_time_machine"
        case .upNext: "smart_up_next"
        case .playlists: "libraryview_playlists"
        case .favoriteAlbums: "library_favorite_albums"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "play.rectangle.fill"
        case .quickAccess: "square.grid.2x2.fill"
        case .quickPicks: "sparkles"
        case .forYou: "person.crop.square"
        case .recentlyPlayed: "clock"
        case .artists: "person.2.fill"
        case .recentlyAdded: "plus.circle"
        case .discovery: "safari"
        case .albums, .revisitAlbums, .onlineAlbums: "square.stack.fill"
        case .favorites, .favoriteAlbums: "heart.fill"
        case .podcasts: "dot.radiowaves.left.and.right"
        case .hiddenGems: "diamond.fill"
        case .listeningWeek: "chart.bar.fill"
        case .vibe: "sun.max.fill"
        case .surprise: "dice.fill"
        case .flow: "waveform"
        case .timeMachine: "clock.arrow.circlepath"
        case .upNext: "list.bullet"
        case .playlists: "music.note.list"
        }
    }
}

struct HomeConfiguration: Equatable {
    static let storageKey = "homeConfiguration.v1"
    static let minimumSections = 2
    static let defaults = Self(sections: [
        .nowPlaying, .quickAccess, .quickPicks, .forYou, .recentlyPlayed, .artists, .recentlyAdded,
        .discovery, .albums, .favorites, .podcasts, .onlineAlbums, .hiddenGems, .revisitAlbums,
        .listeningWeek, .vibe, .surprise, .flow, .timeMachine, .upNext
    ])
    private(set) var sections: [HomeSection]

    static func decode(_ value: String) -> Self {
        guard let data = value.data(using: .utf8),
              let identifiers = try? JSONDecoder().decode([String].self, from: data) else { return defaults }
        var seen = Set<HomeSection>()
        let sections = identifiers.compactMap(HomeSection.init(rawValue:)).filter { seen.insert($0).inserted }
        guard sections.count >= minimumSections else { return defaults }
        return Self(sections: sections)
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(sections.map(\.rawValue)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    mutating func add(_ section: HomeSection) {
        guard !sections.contains(section) else { return }
        sections.append(section)
    }

    mutating func remove(_ section: HomeSection) {
        guard sections.count > Self.minimumSections else { return }
        sections.removeAll { $0 == section }
    }

    mutating func reorder(_ sections: [HomeSection]) {
        guard sections.count == self.sections.count, Set(sections) == Set(self.sections) else { return }
        self.sections = sections
    }
}
