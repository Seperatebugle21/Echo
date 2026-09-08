import SwiftUI

struct ScrollingText: View {

    let text: String

    private let pauseDuration: Double = 2.5
    private let pointsPerSecond: CGFloat = 25
    private let spacing: CGFloat = 40

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    @State private var scrollTask: Task<Void, Never>?


    var body: some View {

        GeometryReader { geometry in

            HStack(spacing: spacing) {

                measuredText

                if textWidth > geometry.size.width {

                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .offset(x: offset)
            .onAppear {

                containerWidth =
                    geometry.size.width

                restartScrolling()
            }
            .onChange(
                of: geometry.size.width
            ) { _, newWidth in

                containerWidth =
                    newWidth

                restartScrolling()
            }
            .onChange(
                of: text
            ) { _, _ in

                offset = 0

                restartScrolling()
            }
        }
        .clipped()
        .onDisappear {

            scrollTask?.cancel()
            scrollTask = nil
        }
    }


    // MARK: - Text

    private var measuredText: some View {

        Text(text)
            .lineLimit(1)
            .fixedSize()
            .background {

                GeometryReader { geometry in

                    Color.clear
                        .onAppear {

                            updateTextWidth(
                                geometry.size.width
                            )
                        }
                        .onChange(
                            of: geometry.size.width
                        ) { _, newWidth in

                            updateTextWidth(
                                newWidth
                            )
                        }
                }
            }
    }


    // MARK: - Width

    private func updateTextWidth(
        _ width: CGFloat
    ) {

        guard abs(textWidth - width) > 0.5 else {

            return
        }

        textWidth = width

        restartScrolling()
    }


    // MARK: - Restart

    private func restartScrolling() {

        scrollTask?.cancel()

        offset = 0

        guard
            textWidth > 0,
            containerWidth > 0,
            textWidth > containerWidth
        else {

            return
        }


        scrollTask = Task {

            await runScrollLoop()
        }
    }


    // MARK: - Scroll Loop

    @MainActor
    private func runScrollLoop() async {

        while !Task.isCancelled {

            // MARK: Pause at beginning

            try? await Task.sleep(
                for: .seconds(
                    pauseDuration
                )
            )


            guard !Task.isCancelled else {

                return
            }


            // MARK: Scroll

            let distance =
                textWidth + spacing


            let duration =
                Double(
                    distance
                    /
                    pointsPerSecond
                )


            withAnimation(
                .linear(
                    duration: duration
                )
            ) {

                offset =
                    -distance
            }


            // Wait until animation is finished.

            try? await Task.sleep(
                for: .seconds(
                    duration
                )
            )


            guard !Task.isCancelled else {

                return
            }


            // MARK: Reset invisibly
            //
            // At this exact moment the second
            // title is in exactly the same place
            // as the first title originally was.

            var transaction =
                Transaction()

            transaction.disablesAnimations =
                true


            withTransaction(
                transaction
            ) {

                offset = 0
            }


            // Loop starts again.
            // It will now wait 2.5 seconds before
            // scrolling for the next cycle.
        }
    }
}
