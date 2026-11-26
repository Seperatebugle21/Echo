import SwiftUI

/// Every past day, newest first. Old days can be played but do not count for the streak.
struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onPick: (Int) -> Void

    var body: some View {
        let strings = model.strings
        let _ = model.saveRevision
        NavigationStack {
            List {
                ForEach((0...model.today).reversed(), id: \.self) { day in
                    Button { onPick(day) } label: { row(day) }
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(strings.archive)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(strings.done) { dismiss() } }
            }
        }
    }

    private func row(_ day: Int) -> some View {
        let strings = model.strings
        let saved = model.savedDay(day)
        let date = PuzzleCalendar.date(forDay: day)
        return HStack(spacing: 14) {
            Text("#\(day + 1)")
                .font(Theme.roundedFont(16, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(day == model.today ? strings.today : date.formatted(.dateTime.day().month(.wide).year()
                    .locale(Locale(identifier: model.language.rawValue))))
                    .font(Theme.roundedFont(16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let saved, saved.status == .finished {
                    Text(saved.resultSquares).font(.system(size: 13))
                } else {
                    Text(saved == nil ? strings.notPlayed : strings.inProgress)
                        .font(Theme.roundedFont(13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
            if let saved, saved.status == .finished {
                Text("\(saved.score)")
                    .font(Theme.roundedFont(16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}
