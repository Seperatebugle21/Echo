import SwiftUI

@main
struct SchakelApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeView()
            .fullScreenCover(isPresented: Binding(
                get: { model.session != nil },
                set: { if !$0 { model.closeGame() } }
            )) {
                GameView()
                    .environment(model)
                    .preferredColorScheme(model.appearance.colorScheme)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.refreshDay() }
            }
    }
}
