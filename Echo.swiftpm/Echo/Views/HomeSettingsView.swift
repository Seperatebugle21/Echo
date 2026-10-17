import SwiftUI

struct HomeSettingsView: View {
    @AppStorage(HomeConfiguration.storageKey) private var storedLayout = ""
    @State private var showSectionPicker = false
    private var configuration: HomeConfiguration { .decode(storedLayout) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        CustomizationIcon(symbol: "house.fill", size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("home_editor_intro_title").font(.title2.bold())
                            Text("customization_home_count \(configuration.sections.count)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text("home_editor_intro_detail").font(.subheadline).foregroundStyle(.secondary)
                    CustomizationHomePreview(sections: configuration.sections)
                    Button { showSectionPicker = true } label: {
                        Label("home_customization_available", systemImage: "plus")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(configuration.sections.count == HomeSection.allCases.count)
                    .accessibilityIdentifier("home-layout-add")
                }
                .padding(18).customizationSurface()
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section {
                ForEach(configuration.sections) { section in
                    HStack(spacing: 12) {
                        HomeSectionDescription(section: section)
                        Button(role: .destructive) { update { $0.remove(section) } } label: {
                            Image(systemName: "minus.circle.fill").font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(configuration.sections.count <= HomeConfiguration.minimumSections)
                        .accessibilityLabel(Text("home_customization_remove \(Text(LocalizedStringKey(section.titleKey)))"))
                        .accessibilityIdentifier("home-layout-remove-" + section.rawValue)
                    }.padding(.vertical, 6)
                }
                .onMove { source, destination in
                    var sections = configuration.sections
                    sections.move(fromOffsets: source, toOffset: destination)
                    update { $0.reorder(sections) }
                }
            } header: {
                Text("home_customization_sections")
            } footer: {
                Text("home_customization_detail")
            }
            .environment(\.editMode, .constant(.active))
        }
        .echoBackground()
        .navigationTitle("home_customization_title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSectionPicker) { HomeSectionPicker() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("tabbarsettingsview_restore_defaults", systemImage: "arrow.counterclockwise") {
                        storedLayout = HomeConfiguration.defaults.encoded
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }.accessibilityLabel("home_editor_options")
            }
        }
    }

    private func update(_ change: (inout HomeConfiguration) -> Void) {
        var next = configuration
        change(&next)
        storedLayout = next.encoded
    }
}

private struct HomeSectionDescription: View {
    let section: HomeSection
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CustomizationIcon(symbol: section.symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(section.titleKey)).font(.headline)
                Text(LocalizedStringKey(section.detailKey)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
}

private struct HomeSectionPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HomeConfiguration.storageKey) private var storedLayout = ""
    @State private var query = ""
    private var configuration: HomeConfiguration { .decode(storedLayout) }
    private var available: [HomeSection] {
        HomeSection.allCases.filter {
            !configuration.sections.contains($0) &&
                (query.isEmpty || EchoLocalization.string($0.titleKey).localizedStandardContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("home_editor_add_detail").font(.subheadline).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(available) { section in
                        Button {
                            var next = configuration
                            next.add(section)
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { storedLayout = next.encoded }
                        } label: {
                            HStack(spacing: 12) {
                                HomeSectionDescription(section: section)
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                            }.padding(.vertical, 6).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("home_customization_add \(Text(LocalizedStringKey(section.titleKey)))"))
                        .accessibilityIdentifier("home-layout-add-" + section.rawValue)
                    }
                }
            }
            .overlay {
                if available.isEmpty {
                    ContentUnavailableView(LocalizedStringKey(query.isEmpty ? "home_editor_all_added" : "catalog_no_search_results"),
                                           systemImage: query.isEmpty ? "checkmark.circle" : "magnifyingglass")
                }
            }
            .searchable(text: $query, prompt: "home_editor_search")
            .echoBackground()
            .navigationTitle("home_customization_available")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action_done") { dismiss() } } }
        }
    }
}
