import SwiftUI
import UIKit

struct HomeCardLayout {
    let width: CGFloat
    var song: CGFloat { min(180, max(96, (width - 64) / 3.15)) }
    var access: CGFloat { min(140, max(78, (width - 70) / 4)) }
    var mix: CGFloat { min(240, max(156, (width - 52) / 2.12)) }
}

struct HomePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct HomeSectionTitle: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
    }
}

struct HomeSectionLink<Destination: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink { destination().toolbarVisibility(.visible, for: .navigationBar) } label: {
            HStack {
                HomeSectionTitle(title: title)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }.frame(minHeight: 36).contentShape(.rect)
        }.buttonStyle(HomePressStyle()).padding(.horizontal, 20)
    }
}

/// A scrim makes text readable over any real artwork; the page still uses Echo's theme.
struct HomeArtworkSurface: View {
    let song: Song?
    var accent = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.accentColor.opacity(accent ? 0.6 : 0.18)
                if let song {
                    SongArtworkView(song: song, cornerRadius: 0)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                if accent { Color.accentColor.opacity(0.18) }
            }.clipped()
        }.accessibilityHidden(true)
    }
}

struct HomeQuickAccessCard: View {
    let title: LocalizedStringKey
    let symbol: String
    let count: Int
    let playlists: Bool
    let song: Song?
    let width: CGFloat
    var accent = false
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent ? Color.accentColor : .black)
                .frame(width: 32, height: 32).background(.white.opacity(0.96), in: .circle)
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            Text(title).font(.caption.weight(.bold)).lineLimit(2)
            Text(verbatim: String(format: String(localized: playlists ? "libraryview_playlists_count" : "libraryview_songs_count"), count))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(9).frame(width: width, height: height, alignment: .leading)
        .background { HomeArtworkSurface(song: song, accent: accent) }
        .clipShape(.rect(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }
}

struct HomeSongRail: View {
    let songs: [Song]
    let width: CGFloat
    let play: (Song) -> Void
    let options: (Song) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(songs) { song in
                    HomeSongTile(song: song, width: width, play: { play(song) }, options: { options(song) })
                }
            }.padding(.horizontal, 20).padding(.vertical, 3)
        }.scrollIndicators(.hidden)
    }
}

private struct HomeSongTile: View {
    let song: Song
    let width: CGFloat
    let play: () -> Void
    let options: () -> Void
    @Environment(AudioPlayerManager.self) private var player
    @Environment(MiniPlayerPresentation.self) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source = HomeCoverGeometry()

    var body: some View {
        Button(action: launch) {
            VStack(alignment: .leading, spacing: 5) {
                SongArtworkView(song: song, cornerRadius: 13).frame(width: width, height: width)
                    .accessibilityHidden(true)
                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: width, alignment: .leading).contentShape(.rect)
        }
        .buttonStyle(HomePressStyle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { source.frame = $0 }
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in options() })
        .accessibilityLabel(Text("\(song.title), \(song.artist)"))
        .accessibilityHint("home_song_options_hint")
        .accessibilityAction(named: Text("home_song_options")) { options() }
    }

    private func launch() {
        if player.currentSong == nil && !reduceMotion && source.frame.width > 0 {
            presentation.entranceFrame = CGRect(origin: source.frame.origin, size: CGSize(width: width, height: width))
            presentation.entranceImage = (song.coverData ?? song.imageData).flatMap { UIImage(data: $0) }
            presentation.entranceSong = song
        }
        play()
        if player.currentSong?.id != song.id {
            presentation.entranceSong = nil
            presentation.entranceImage = nil
        }
    }
}

private final class HomeCoverGeometry { var frame: CGRect = .zero }

struct HomePersonalMix: Identifiable {
    enum Kind: String, CaseIterable {
        case daily, similar, rediscover
        var title: LocalizedStringKey { LocalizedStringKey("home_mix_" + rawValue) }
        var description: LocalizedStringKey { LocalizedStringKey("home_mix_" + rawValue + "_detail") }
    }
    let kind: Kind
    let songs: [Song]
    var id: Kind { kind }
}

struct HomeForYouSection: View {
    let mixes: [HomePersonalMix]
    let width: CGFloat
    let play: (Song, [Song]) -> Void
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180
    @State private var playbackFeedback = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionTitle(title: "home_for_you").padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(mixes) { mix in
                        ZStack(alignment: .topLeading) {
                            NavigationLink {
                                HomeMixCollectionView(kind: mix.kind)
                                    .toolbarVisibility(.visible, for: .navigationBar)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Spacer(minLength: 50)
                                    Text(mix.kind.title).font(.title3.bold()).lineLimit(2)
                                    Text(mix.kind.description).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                                }
                                .foregroundStyle(.white).padding(14)
                                .frame(width: width, height: height, alignment: .bottomLeading)
                                .background { HomeArtworkSurface(song: mix.songs.first) }
                                .clipShape(.rect(cornerRadius: 18))
                            }.buttonStyle(HomePressStyle())
                            Button {
                                if let first = mix.songs.first { play(first, mix.songs); playbackFeedback += 1 }
                            } label: {
                                Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.black).frame(width: 36, height: 36).background(.white, in: .circle)
                            }.buttonStyle(HomePressStyle()).padding(14)
                                .accessibilityLabel(Text("home_play_mix \(Text(mix.kind.title))"))
                        }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 3)
            }.scrollIndicators(.hidden)
        }.sensoryFeedback(.selection, trigger: playbackFeedback)
    }
}

/// Resolve session IDs again so deleted tracks cannot linger in an open collection.
private struct HomeMixCollectionView: View {
    let kind: HomePersonalMix.Kind
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var player
    @State private var selectedSong: Song?
    private var songs: [Song] {
        let available = library.songs.filter {
            $0.podcastEpisodeID == nil && library.getURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
        let mixes = HomeSessionManager.shared.mixes(songs: available, favoriteSongIDs: library.favoriteSongIDs,
                                                   recommendationManager: .shared)
        let index = HomePersonalMix.Kind.allCases.firstIndex(of: kind) ?? 0
        return mixes[index]
    }
    var body: some View {
        List {
            if let first = songs.first {
                Button { play(first) } label: { Label("action_play_now", systemImage: "play.fill") }
                    .foregroundStyle(Color.accentColor)
            }
            ForEach(songs) { song in
                HStack {
                    Button { play(song) } label: { LibrarySongRow(song: song) }.buttonStyle(.plain)
                    Button { selectedSong = song } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("home_song_options")
                }
            }
        }.echoBackground().navigationTitle(kind.title)
            .sheet(item: $selectedSong) { SongOptionsView(song: $0) }
            .sheet(item: Bindable(library).songToAddToPlaylist) { PlaylistPickerView(songs: [$0]) }
            .sheet(isPresented: Bindable(library).showEditSheet) {
                if let song = library.editingSong { EditSongView(song: song) }
            }
    }
    private func play(_ song: Song) {
        guard let url = library.getURL(for: song) else { return }
        player.lastPlaybackDirection = .fade
        player.play(song: song, url: url, queue: songs)
        player.allSongs = library.songs
        player.fillAutoNext(from: library.songs)
    }
}
