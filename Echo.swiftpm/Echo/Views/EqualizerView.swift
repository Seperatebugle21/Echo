import SwiftUI

struct EqualizerView: View {
    @State private var settings = EqualizerSettings.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tint = LinearGradient(colors: [.accentColor, .cyan], startPoint: .bottomLeading, endPoint: .topTrailing)
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    Image(systemName: "slider.vertical.3").font(.title).foregroundStyle(tint)
                        .frame(width: 52, height: 52).background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("equalizerview_title").font(.headline)
                        Text(settings.configuration.preset.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("equalizerview_enabled", isOn: Binding(get: { settings.configuration.enabled }, set: { settings.setEnabled($0) })).labelsHidden()
                }.padding(18).background(.thinMaterial, in: .rect(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 18) {
                    EqualizerCurve(gains: settings.configuration.gains).frame(height: 150)
                    if typeSize.isAccessibilitySize {
                        ForEach(EqualizerBand.allCases) { band in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text("equalizerview_frequency \(Int(band.frequency))"); Spacer(); gainText(band) }
                                Slider(value: gainBinding(band), in: -12...12, step: 0.5)
                                    .accessibilityLabel(Text("equalizerview_frequency \(Int(band.frequency))"))
                            }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(EqualizerBand.allCases) { band in
                                VStack(spacing: 8) {
                                    gainText(band).font(.caption.monospacedDigit())
                                    EqualizerFader(gain: gainBinding(band), band: band).frame(height: 150)
                                    Text("equalizerview_frequency \(Int(band.frequency))").font(.caption2).lineLimit(1)
                                }.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    Text("equalizerview_headroom_hint").font(.footnote).foregroundStyle(.secondary)
                }.padding(18).background(.thinMaterial, in: .rect(cornerRadius: 24))
                    .disabled(!settings.configuration.enabled).opacity(settings.configuration.enabled ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 12) {
                    Text("equalizerview_preset").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 220 : 140))], spacing: 10) {
                        ForEach(EqualizerPreset.allCases.filter { $0 != .custom }) { preset in
                            Button { settings.select(preset) } label: {
                                HStack {
                                    Text(preset.title).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                                    Spacer(minLength: 4)
                                    if settings.configuration.preset == preset { Image(systemName: "checkmark.circle.fill") }
                                }.padding(14).frame(maxWidth: .infinity, minHeight: 48)
                                    .background(settings.configuration.preset == preset ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04), in: .rect(cornerRadius: 16))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(settings.configuration.preset == preset ? [.isSelected] : [])
                        }
                    }
                }.padding(18).background(.thinMaterial, in: .rect(cornerRadius: 24))
                Text("equalizerview_saved_hint").font(.footnote).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.echoBackground().navigationTitle("equalizerview_title").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("equalizerview_reset") { settings.select(.flat) } } }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settings.configuration.enabled)
            .onDisappear { settings.flush() }
    }
    private func gainBinding(_ band: EqualizerBand) -> Binding<Double> {
        Binding(get: { Double(settings.configuration.gains[band.rawValue]) }, set: { settings.setGain(Float($0), for: band) })
    }
    private func gainText(_ band: EqualizerBand) -> Text { Text("equalizerview_gain \(Double(settings.configuration.gains[band.rawValue]), specifier: "%.1f")") }
}

private struct EqualizerCurve: View {
    let gains: [Float]
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let points = gains.enumerated().map { i, value in CGPoint(x: CGFloat(i) / 5 * width, y: 18 + CGFloat(12 - value) / 24 * (height - 36)) }
            let curve = Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for i in 1..<points.count {
                    let a = points[i - 1], b = points[i], mid = (a.x + b.x) / 2
                    path.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
                }
            }
            ZStack {
                Path { path in for y in [CGFloat(18), height / 2, height - 18] { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y)) } }
                    .stroke(.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                Path { path in
                    path.addPath(curve); path.addLine(to: CGPoint(x: width, y: height)); path.addLine(to: CGPoint(x: 0, y: height)); path.closeSubpath()
                }.fill(LinearGradient(colors: [.accentColor.opacity(0.25), .cyan.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                curve.stroke(LinearGradient(colors: [.accentColor, .cyan], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }.accessibilityHidden(true)
    }
}

private struct EqualizerFader: View {
    @Binding var gain: Double
    let band: EqualizerBand
    var body: some View {
        GeometryReader { geometry in
            let height = max(1, geometry.size.height - 24)
            let y = 12 + CGFloat(12 - gain) / 24 * height
            ZStack(alignment: .top) {
                Capsule().fill(.primary.opacity(0.08)).frame(width: 5).padding(.vertical, 12)
                Capsule().fill(LinearGradient(colors: [.accentColor, .cyan], startPoint: .bottom, endPoint: .top))
                    .frame(width: 5, height: max(1, geometry.size.height - y - 12)).offset(y: y)
                RoundedRectangle(cornerRadius: 8).fill(.regularMaterial).frame(width: 30, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.2), lineWidth: 1))
                    .overlay(Capsule().fill(.secondary).frame(width: 12, height: 2)).offset(y: y - 11)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in gain = min(12, max(-12, ((12 - Double((value.location.y - 12) / height) * 24) * 2).rounded() / 2)) })
        }.frame(minWidth: 44)
            .accessibilityElement().accessibilityLabel(Text("equalizerview_frequency \(Int(band.frequency))"))
            .accessibilityValue(Text("equalizerview_gain \(gain, specifier: "%.1f")"))
            .accessibilityAdjustableAction { action in switch action { case .increment: gain = min(12, gain + 0.5); case .decrement: gain = max(-12, gain - 0.5); @unknown default: break } }
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
