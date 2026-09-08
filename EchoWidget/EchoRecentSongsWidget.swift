import SwiftUI
import UIKit
import WidgetKit

struct EchoRecentSongsWidget: Widget {

    private let kind =
        "com.echomusic.app.widget.recent-songs"

    var body: some WidgetConfiguration {

        StaticConfiguration(
            kind: kind,
            provider: EchoWidgetProvider()
        ) { entry in

            EchoRecentSongsWidgetView(entry: entry)
                .containerBackground(
                    Color.black,
                    for: .widget
                )
        }
        .configurationDisplayName("Recente nummers")
        .description(
            "Speel een van je vier recente nummers meteen af."
        )
        .supportedFamilies([
            .systemMedium
        ])
        .contentMarginsDisabled()
    }
}

private struct EchoRecentSongsWidgetView: View {

    let entry: EchoWidgetEntry

    private var songs: [EchoWidgetSongItem] {
        Array(entry.snapshot.songs.prefix(4))
    }

    var body: some View {

        GeometryReader { proxy in

            let spacing: CGFloat = 7
            let tileWidth = max(
                0,
                (proxy.size.width - spacing * 3) / 4
            )

            HStack(spacing: spacing) {

                ForEach(0..<4, id: \.self) { index in

                    if index < songs.count {
                        songTile(
                            songs[index],
                            width: tileWidth
                        )

                    } else {

                        EchoWidgetArtwork(artworkData: nil)
                            .frame(
                                width: tileWidth,
                                height: tileWidth
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                            )
                            .opacity(0.55)
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .widgetURL(
            URL(string: "echo://open")
        )
    }

    private func songTile(
        _ song: EchoWidgetSongItem,
        width: CGFloat
    ) -> some View {

        Link(destination: song.playbackURL) {

            EchoWidgetArtwork(
                artworkData: song.artworkData
            )
            .frame(
                width: width,
                height: width
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )
        }
        .accessibilityLabel(
            "Speel \(song.title) van \(song.artist)"
        )
    }
}

private struct EchoWidgetArtwork: View {

    let artworkData: Data?

    var body: some View {

        if
            let artworkData,
            let image = UIImage(data: artworkData)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()

        } else {

            ZStack {
                LinearGradient(
                    colors: [
                        Color.red,
                        Color.red.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "music.note")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
