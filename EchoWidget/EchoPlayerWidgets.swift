import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct EchoRoundedPlayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: EchoWidgetKinds.rounded, provider: EchoWidgetProvider()) {
            EchoPlayerWidgetView(entry: $0, style: .rounded)
        }
        .configurationDisplayName("Speler · Zachte cover")
        .description("Albumcover, favoriet en muziekbediening op een gekleurde achtergrond.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct EchoCoverPlayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: EchoWidgetKinds.cover, provider: EchoWidgetProvider()) {
            EchoPlayerWidgetView(entry: $0, style: .cover)
        }
        .configurationDisplayName("Speler · Albumcover")
        .description("Een grote albumcover met titel en artiest. Tik om Echo te openen.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct EchoEdgePlayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: EchoWidgetKinds.edge, provider: EchoWidgetProvider()) {
            EchoPlayerWidgetView(entry: $0, style: .edge)
        }
        .configurationDisplayName("Speler · Volle cover")
        .description("Een brede speler met randvullende cover en afspeelknoppen.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct EchoCompactPlayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: EchoWidgetKinds.compact, provider: EchoWidgetProvider()) {
            EchoPlayerWidgetView(entry: $0, style: .compact)
        }
        .configurationDisplayName("Speler · Compact")
        .description("Cover, favoriet en vorige, pauze en volgende in een kleine widget.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

enum EchoPlayerStyle { case rounded, cover, edge, compact }

struct EchoPlayerWidgetView: View {
    let entry: EchoWidgetEntry
    let style: EchoPlayerStyle
    private var song: EchoWidgetSongItem? { entry.snapshot.currentSong ?? entry.snapshot.songs.first }
    private var playing: Bool { entry.snapshot.isPlaying == true }

    var body: some View {
        Group {
            if let song {
                GeometryReader { proxy in
                    switch style {
                    case .cover:
                        EchoWidgetArtwork(song: song)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .overlay(alignment: .bottomLeading) {
                                metadata(song).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.9)],
                                                              startPoint: .top, endPoint: .bottom))
                            }
                            .accessibilityHidden(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Open Echo: \(song.title) van \(song.artist)")
                    case .compact:
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top) {
                                EchoWidgetArtwork(song: song)
                                    .frame(width: max(32, proxy.size.height * 0.32), height: max(32, proxy.size.height * 0.32))
                                    .clipShape(.rect(cornerRadius: 7))
                                Spacer(minLength: 0)
                                favorite(song)
                            }
                            Spacer(minLength: 2)
                            metadata(song)
                            controls(song)
                        }
                        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
                    case .rounded, .edge:
                        HStack(spacing: style == .rounded ? 8 : 0) {
                            EchoWidgetArtwork(song: song)
                                .frame(width: style == .rounded ? proxy.size.height - 28 : proxy.size.width * 0.44,
                                       height: style == .rounded ? proxy.size.height - 28 : proxy.size.height)
                                .clipShape(.rect(cornerRadius: style == .rounded ? 12 : 0))
                                .padding(.leading, style == .rounded ? 14 : 0)
                            VStack(spacing: 0) {
                                HStack { Spacer(minLength: 0); favorite(song) }
                                Spacer(minLength: 0)
                                metadata(song, centered: true)
                                Spacer(minLength: 0)
                                controls(song)
                            }
                            .padding(.horizontal, 6).padding(.bottom, 8)
                        }
                    }
                }
            } else {
                EchoWidgetEmptyView(sharedContainerAvailable: entry.sharedContainerAvailable)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { EchoWidgetBackground(song: song) }
        .widgetURL(URL(string: "echo://open"))
    }

    private func metadata(_ song: EchoWidgetSongItem, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 2) {
            Text(verbatim: song.title).font(.caption.weight(.bold)).lineLimit(1)
            Text(verbatim: song.artist).font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func favorite(_ song: EchoWidgetSongItem) -> some View {
        Button(intent: EchoWidgetPlaybackIntent(.favorite, songID: song.id)) {
            Image(systemName: song.isFavorite == true ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(song.isFavorite == true ? Color.red : .white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(song.isFavorite == true ? "Verwijder uit favorieten" : "Voeg toe aan favorieten")
    }

    private func controls(_ song: EchoWidgetSongItem) -> some View {
        HStack(spacing: 0) {
            control(.previous, symbol: "backward.end.fill", label: "Vorig nummer", song: song)
            control(.toggle, symbol: playing ? "pause.fill" : "play.fill",
                    label: playing ? "Pauzeer" : "Speel af", song: song)
            control(.next, symbol: "forward.end.fill", label: "Volgend nummer", song: song)
        }
    }

    private func control(_ action: EchoWidgetAction, symbol: String, label: String,
                         song: EchoWidgetSongItem) -> some View {
        Button(intent: EchoWidgetPlaybackIntent(action, songID: song.id)) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

struct EchoWidgetArtwork: View {
    let song: EchoWidgetSongItem?
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let data = song?.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.5, green: 0.18, blue: 0.42),
                                                Color(red: 0.13, green: 0.18, blue: 0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .accessibilityHidden(true)
    }
}

struct EchoWidgetBackground: View {
    let song: EchoWidgetSongItem?
    var body: some View {
        EchoWidgetArtwork(song: song).blur(radius: 24)
            .overlay(.black.opacity(0.58))
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
    }
}

struct EchoWidgetEmptyView: View {
    let sharedContainerAvailable: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: sharedContainerAvailable ? "music.note" : "exclamationmark.icloud")
                .font(.title2)
            Text(sharedContainerAvailable ? "Je muziek, dichtbij" : "Widget niet gekoppeld")
                .font(.headline)
            Text(sharedContainerAvailable ? "Open Echo en voeg muziek toe." : "Echo en deze widget kunnen nog geen muziekgegevens delen. Werk Echo bij en open de app.")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct EchoQuickPicksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: EchoWidgetKinds.quickPicks, provider: EchoWidgetProvider()) { entry in
            EchoQuickPicksView(entry: entry)
        }
        .configurationDisplayName("Quick Picks")
        .description("Jouw Quick Picks uit Echo. Tik op een cover om dat nummer af te spelen.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct EchoQuickPicksView: View {
    let entry: EchoWidgetEntry
    var body: some View {
        Group {
            if entry.snapshot.songs.isEmpty {
                EchoWidgetEmptyView(sharedContainerAvailable: entry.sharedContainerAvailable)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Quick Picks").font(.caption.weight(.bold))
                        Spacer()
                        Image(systemName: "waveform").foregroundStyle(.white.opacity(0.65))
                    }
                    GeometryReader { proxy in
                        let width = max(0, (proxy.size.width - 24) / 4)
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(Array(entry.snapshot.songs.prefix(4))) { song in
                                Button(intent: EchoWidgetPlaybackIntent(.play, songID: song.id)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        EchoWidgetArtwork(song: song)
                                            .frame(width: width, height: min(width, max(24, proxy.size.height - 18)))
                                            .clipShape(.rect(cornerRadius: 9))
                                        Text(verbatim: song.title).font(.caption2).lineLimit(1)
                                    }
                                    .frame(width: width)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Speel \(song.title) van \(song.artist)")
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { EchoWidgetBackground(song: entry.snapshot.songs.first) }
        .widgetURL(URL(string: "echo://open"))
    }
}
