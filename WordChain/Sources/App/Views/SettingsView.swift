import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        let strings = model.strings
        let graph = model.graph(for: model.language)
        NavigationStack {
            Form {
                Section {
                    Picker(strings.languageTitle, selection: $model.language) {
                        ForEach(GameLanguage.allCases) { language in
                            Text("\(language.flag)  \(language.nativeName)").tag(language)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(strings.languageTitle)
                } footer: {
                    Text(strings.languageFooter)
                }

                Section(strings.appearance) {
                    Picker(strings.appearance, selection: $model.appearance) {
                        Text(strings.system).tag(AppearanceSetting.system)
                        Text(strings.light).tag(AppearanceSetting.light)
                        Text(strings.dark).tag(AppearanceSetting.dark)
                    }
                    .pickerStyle(.segmented)
                    Toggle(strings.haptics, isOn: $model.hapticsEnabled)
                }

                Section(strings.wordList) {
                    LabeledContent(strings.wordList, value: strings.wordListSize(words: graph.words.count, links: graph.linkCount))
                    Text(strings.roundCapacity(capacity))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Versie / Version",
                                   value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(strings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(strings.done) { dismiss() } }
            }
            .animation(.default, value: model.language)
        }
    }

    /// Rounded down to a round number so it reads well.
    private var capacity: Int {
        let total = model.generator(for: model.language).capacity().values.reduce(0, +)
        let magnitude = max(1, Int(pow(10, floor(log10(Double(max(total, 1)))))))
        return total / magnitude * magnitude
    }
}
