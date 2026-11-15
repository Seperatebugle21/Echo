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
    }
}
