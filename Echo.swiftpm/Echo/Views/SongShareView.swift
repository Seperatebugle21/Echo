import SwiftUI
import UIKit

/// What a share card shows: a song, optionally with a few lyric lines.
struct SongSharePayload: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let artworkData: Data?
    /// Every lyric line that may be picked; empty for a plain song card.
    var lyricLines: [String] = []
    /// Lines selected when the sheet opens.
    var initialLyricSelection: Set<Int> = []

    init(song: Song, lyricLines: [String] = [], initialLyricSelection: Set<Int> = []) {
        title = song.title
        artist = song.artist
        artworkData = song.coverData ?? song.imageData
        self.lyricLines = lyricLines
        self.initialLyricSelection = initialLyricSelection
    }
}

enum ShareCardStyle: String, CaseIterable, Identifiable {
    case artwork, midnight, accent
    var id: String { rawValue }
    var titleKey: LocalizedStringKey {
        switch self {
        case .artwork: "share_style_artwork"
        case .midnight: "share_style_midnight"
        case .accent: "share_style_accent"
        }
    }
}

/// Gradient colours for a card, taken from the cover where possible.
struct ShareCardColors {
    var top: Color
    var bottom: Color

    static func make(style: ShareCardStyle, palette: ArtworkPalette?) -> ShareCardColors {
        switch style {
        case .midnight:
            return ShareCardColors(top: Color(white: 0.16), bottom: .black)
        case .accent:
            return ShareCardColors(top: Color.accentColor, bottom: Color.accentColor.mix(with: .black, by: 0.65))
        case .artwork:
            let colours = palette?.darkBackground ?? []
            guard let first = colours.first else {
                return ShareCardColors(top: Color(red: 0.32, green: 0.18, blue: 0.42), bottom: .black)
            }
            let second = colours.dropFirst().first ?? first
            return ShareCardColors(top: Color(red: first.r, green: first.g, blue: first.b),
                                   bottom: Color(red: second.r, green: second.g, blue: second.b).mix(with: .black, by: 0.55))
        }
    }
}

/// The image that is shared. Fixed 9:16 size so it fits stories.
struct SongShareCard: View {
    let title: String
    let artist: String
    let cover: UIImage?
    let lyrics: [String]
    let colors: ShareCardColors

    var body: some View {
        ZStack {
            LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom)
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill()
                    .frame(width: 360, height: 640).blur(radius: 60).opacity(0.35).clipped()
            }
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 0)
                coverView(size: lyrics.isEmpty ? 270 : 92)
                    .frame(maxWidth: .infinity, alignment: lyrics.isEmpty ? .center : .leading)
                if !lyrics.isEmpty {
                    Text(lyrics.joined(separator: "\n"))
                        .font(.system(size: lyrics.count > 2 ? 24 : 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: lyrics.isEmpty ? .center : .leading, spacing: 4) {
                    Text(title).font(.system(size: lyrics.isEmpty ? 24 : 17, weight: .bold))
                    Text(artist).font(.system(size: lyrics.isEmpty ? 18 : 15, weight: .medium)).opacity(0.75)
                }
                .lineLimit(2)
                .multilineTextAlignment(lyrics.isEmpty ? .center : .leading)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: lyrics.isEmpty ? .center : .leading)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 13, weight: .bold))
                    Text(verbatim: "Echo").font(.system(size: 15, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
            }
            .padding(30)
        }
        .frame(width: 360, height: 640)
        .clipShape(.rect)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func coverView(size: CGFloat) -> some View {
        Group {
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size > 120 ? 18 : 10, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}

/// Preview, style choice, lyric line picker and the share button.
struct SongShareSheet: View {
    let payload: SongSharePayload
    @Environment(\.dismiss) private var dismiss
    @State private var style = ShareCardStyle.artwork
    @State private var selection: Set<Int> = []
    @State private var cover: UIImage?
    @State private var palette: ArtworkPalette?
    @State private var rendered: UIImage?
    @State private var shareFeedback = 0

    private static let maximumLyricLines = 4

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    card
                        .scaleEffect(0.78)
                        .frame(width: 360 * 0.78, height: 640 * 0.78)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                        .accessibilityElement(children: .combine)

                    Picker("share_style_title", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { Text($0.titleKey).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !payload.lyricLines.isEmpty { lyricPicker }

                    if let rendered {
                        ShareLink(item: Image(uiImage: rendered),
                                  message: Text(verbatim: "\(payload.title) — \(payload.artist)"),
                                  preview: SharePreview(Text(verbatim: payload.title), image: Image(uiImage: rendered))) {
                            Label("share_action", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .simultaneousGesture(TapGesture().onEnded { shareFeedback += 1 })
                        .sensoryFeedback(.success, trigger: shareFeedback)
                    } else {
                        ProgressView().frame(minHeight: 50)
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(payload.lyricLines.isEmpty ? LocalizedStringKey("share_song_title") : LocalizedStringKey("share_lyrics_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action_done") { dismiss() }.tint(.primary)
                }
            }
        }
        .task {
            selection = payload.initialLyricSelection
            if let data = payload.artworkData {
                let prepared = await Task.detached(priority: .userInitiated) {
                    (UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 900, height: 900)),
                     ArtworkPalette.from(imageData: data))
                }.value
                cover = prepared.0
                palette = prepared.1
            }
            render()
        }
        .onChange(of: style) { render() }
        .onChange(of: selection) { render() }
    }

    private var selectedLines: [String] {
        selection.sorted().compactMap { payload.lyricLines.indices.contains($0) ? payload.lyricLines[$0] : nil }
    }

    private var card: SongShareCard {
        SongShareCard(title: payload.title, artist: payload.artist, cover: cover, lyrics: selectedLines,
                      colors: ShareCardColors.make(style: style, palette: palette))
    }

    private var lyricPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("share_lyrics_pick \(Self.maximumLyricLines)")
                .font(.footnote).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(payload.lyricLines.enumerated()), id: \.offset) { index, line in
                    let selected = selection.contains(index)
                    Button {
                        if selected { selection.remove(index) }
                        else if selection.count < Self.maximumLyricLines { selection.insert(index) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                            Text(line).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!selected && selection.count >= Self.maximumLyricLines)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14, style: .continuous))
            .sensoryFeedback(.selection, trigger: selection)
        }
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        rendered = renderer.uiImage
    }
}
