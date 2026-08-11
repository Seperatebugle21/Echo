import AppIntents

struct EchoShortcuts: AppShortcutsProvider {
    
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Speel muziek met \(.applicationName)"
            ],
            shortTitle: "Speel muziek"
        )
    }
}
