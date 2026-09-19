import SwiftUI

struct EqualizerView: View {
    @State private var settings = EqualizerSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("equalizerview_enabled", isOn: Binding(
                    get: { settings.configuration.enabled },
                    set: { settings.setEnabled($0) }
                ))
            } footer: {
                Text("equalizerview_saved_hint")
            }

            Section {
                EqualizerGraph(settings: settings)
                    .frame(height: 240)
                    .disabled(!settings.configuration.enabled)
                    .opacity(settings.configuration.enabled ? 1 : 0.45)
                HStack {
                    ForEach(EqualizerBand.allCases) { band in
                        Text("equalizerview_frequency \(Int(band.frequency))")
                            .font(.caption2)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            } header: {
                Text("equalizerview_bands")
            } footer: {
                Text("equalizerview_bands_hint")
            }

            Section {
                Picker("equalizerview_preset", selection: Binding(
                    get: { settings.configuration.preset },
                    set: { settings.select($0) }
                )) {
                    ForEach(EqualizerPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                            .disabled(preset == .custom)
                    }
                }
                .pickerStyle(.navigationLink)

                Button("equalizerview_reset") { settings.select(.flat) }
            } footer: {
                Text("equalizerview_headroom_hint")
            }
        }
        .echoBackground()
        .navigationTitle("equalizerview_title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EqualizerGraph: View {
    let settings: EqualizerSettings

    var body: some View {
        GeometryReader { geometry in
            let top: CGFloat = 26
            let height = max(1, geometry.size.height - 52)
            let column = geometry.size.width / CGFloat(EqualizerBand.allCases.count)
            ZStack(alignment: .topLeading) {
                Path { path in
                    for fraction in [CGFloat(0), 0.5, 1] {
                        let y = top + fraction * height
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .accessibilityHidden(true)

                Path { path in
                    for band in EqualizerBand.allCases {
                        let point = CGPoint(
                            x: (CGFloat(band.rawValue) + 0.5) * column,
                            y: top + CGFloat(12 - settings.configuration.gains[band.rawValue]) / 24 * height
                        )
                        if band == .bass { path.move(to: point) }
                        else { path.addLine(to: point) }
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                .accessibilityHidden(true)

                ForEach(EqualizerBand.allCases) { band in
                    let gain = settings.configuration.gains[band.rawValue]
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .position(
                            x: (CGFloat(band.rawValue) + 0.5) * column,
                            y: top + CGFloat(12 - gain) / 24 * height
                        )
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("equalizerGraph"))
                            .onChanged { value in
                                let raw = 12 - Float((value.location.y - top) / height) * 24
                                settings.setGain((raw * 2).rounded() / 2, for: band)
                            }
                        )
                        .accessibilityElement()
                        .accessibilityLabel(Text("equalizerview_frequency \(Int(band.frequency))"))
                        .accessibilityValue(Text("equalizerview_gain \(Double(gain), specifier: "%.1f")"))
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: settings.setGain(gain + 1, for: band)
                            case .decrement: settings.setGain(gain - 1, for: band)
                            @unknown default: break
                            }
                        }
                }
            }
            .coordinateSpace(.named("equalizerGraph"))
            .overlay(alignment: .topLeading) {
                Text("equalizerview_gain_max").font(.caption2).foregroundStyle(.secondary)
            }
            .overlay(alignment: .bottomLeading) {
                Text("equalizerview_gain_min").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private extension EqualizerPreset {
    var title: LocalizedStringKey {
        switch self {
        case .flat: "equalizerview_preset_flat"
        case .bassBoost: "equalizerview_preset_bass_boost"
        case .bassReducer: "equalizerview_preset_bass_reducer"
        case .trebleBoost: "equalizerview_preset_treble_boost"
        case .vocal: "equalizerview_preset_vocal"
        case .acoustic: "equalizerview_preset_acoustic"
        case .pop: "equalizerview_preset_pop"
        case .rock: "equalizerview_preset_rock"
        case .electronic: "equalizerview_preset_electronic"
        case .custom: "equalizerview_preset_custom"
        }
    }
}
