import SwiftUI
import WidgetKit

@main
struct EchoWidgets: WidgetBundle {

    var body: some Widget {
        EchoLockScreenWidget()
        EchoRoundedPlayerWidget()
        EchoCoverPlayerWidget()
        EchoEdgePlayerWidget()
        EchoCompactPlayerWidget()
        EchoQuickPicksWidget()
        EchoDownloadActivityWidget()
        // Nested, so the bundle stays within the result builder's item limit.
        EchoControlsBundle().body
    }
}
