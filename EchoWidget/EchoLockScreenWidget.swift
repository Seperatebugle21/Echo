import Foundation
import SwiftUI
import WidgetKit

struct EchoLockScreenWidget: Widget {

    private let kind =
        "com.echomusic.app.widget.lock-screen"

    var body: some WidgetConfiguration {

        StaticConfiguration(
            kind: kind,
            provider: EchoWidgetProvider()
        ) { entry in

            EchoLockScreenWidgetView(entry: entry)
                .containerBackground(
                    .clear,
                    for: .widget
                )
        }
        .configurationDisplayName("Echo openen")
        .description(
            "Open Echo rechtstreeks vanaf je toegangsscherm."
        )
        .supportedFamilies([
            .accessoryCircular
        ])
    }
}

private struct EchoLockScreenWidgetView: View {

    let entry: EchoWidgetEntry

    var body: some View {

        ZStack {
            AccessoryWidgetBackground()

            Image("EchoMark")
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .padding(3)
        }
        .widgetURL(
            URL(string: "echo://open")
        )
        .accessibilityLabel("Open Echo")
    }
}
