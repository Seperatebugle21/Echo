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

        EchoLockScreenMark()
            .fill(.primary, style: FillStyle(eoFill: true))
            .aspectRatio(1, contentMode: .fit)
            .padding(5)
            .foregroundStyle(.primary)
            .widgetAccentable()
        .widgetURL(
            URL(string: "echo://open")
        )
        .accessibilityLabel("Open Echo")
    }
}

// Vector outline of the app mark, with open note heads and no icon background.
// Coordinates follow the existing EchoMark asset's 1091-point canvas.
private struct EchoLockScreenMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 371, y: 646))
        path.addLine(to: CGPoint(x: 371, y: 338))
        path.addCurve(to: CGPoint(x: 417, y: 272),
                      control1: CGPoint(x: 371, y: 307), control2: CGPoint(x: 389, y: 282))
        path.addLine(to: CGPoint(x: 793, y: 149))
        path.addCurve(to: CGPoint(x: 871, y: 207),
                      control1: CGPoint(x: 837, y: 133), control2: CGPoint(x: 871, y: 155))
        path.addLine(to: CGPoint(x: 871, y: 691))
        path.addCurve(to: CGPoint(x: 724, y: 845),
                      control1: CGPoint(x: 871, y: 779), control2: CGPoint(x: 807, y: 845))
        path.addCurve(to: CGPoint(x: 575, y: 695),
                      control1: CGPoint(x: 640, y: 845), control2: CGPoint(x: 575, y: 778))
        path.addCurve(to: CGPoint(x: 778, y: 552),
                      control1: CGPoint(x: 575, y: 587), control2: CGPoint(x: 678, y: 517))
        path.addLine(to: CGPoint(x: 778, y: 284))
        path.addLine(to: CGPoint(x: 489, y: 377))
        path.addQuadCurve(to: CGPoint(x: 468, y: 402), control: CGPoint(x: 468, y: 383))
        path.addLine(to: CGPoint(x: 468, y: 790))
        path.addCurve(to: CGPoint(x: 310, y: 947),
                      control1: CGPoint(x: 468, y: 881), control2: CGPoint(x: 399, y: 947))
        path.addCurve(to: CGPoint(x: 153, y: 788),
                      control1: CGPoint(x: 220, y: 947), control2: CGPoint(x: 153, y: 877))
        path.addCurve(to: CGPoint(x: 371, y: 646),
                      control1: CGPoint(x: 153, y: 674), control2: CGPoint(x: 267, y: 604))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: 237, y: 716, width: 141, height: 141))
        path.addEllipse(in: CGRect(x: 659, y: 624, width: 131, height: 132))
        return path.applying(CGAffineTransform(scaleX: rect.width / 1091, y: rect.height / 1091))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
