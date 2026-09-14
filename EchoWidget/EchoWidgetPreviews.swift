import SwiftUI
import WidgetKit

#Preview("Zachte cover", as: .systemMedium) { EchoRoundedPlayerWidget() } timeline: {
    EchoWidgetEntry(date: .now, snapshot: .preview)
}
#Preview("Albumcover", as: .systemSmall) { EchoCoverPlayerWidget() } timeline: {
    EchoWidgetEntry(date: .now, snapshot: .preview)
}
#Preview("Volle cover", as: .systemMedium) { EchoEdgePlayerWidget() } timeline: {
    EchoWidgetEntry(date: .now, snapshot: .preview)
}
#Preview("Compact", as: .systemSmall) { EchoCompactPlayerWidget() } timeline: {
    EchoWidgetEntry(date: .now, snapshot: .preview)
}
#Preview("Quick Picks", as: .systemMedium) { EchoQuickPicksWidget() } timeline: {
    EchoWidgetEntry(date: .now, snapshot: .preview)
}
#Preview("Leeg", as: .systemMedium) { EchoQuickPicksWidget() } timeline: {
    EchoWidgetEntry(date: .now, snapshot: .empty)
}
