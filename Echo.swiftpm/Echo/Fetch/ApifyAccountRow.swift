import SwiftUI

struct ApifyAccountRow: View {

    let account: ApifyAccount

    @State private var settings =
        ApifySettings.shared

    @State private var usage:
        ApifyAccountUsage?

    @State private var loading =
        false

    @State private var errorMessage:
        String?

    private var isActive: Bool {

        settings.activeAccountID ==
        account.id
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            HStack {

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {

                    Text(account.name)
                        .font(.headline)

                    Text(
                        maskedToken(
                            account.token
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                if isActive {

                    Label(
                        "apifyaccountrow_active",
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }

            if loading {

                ProgressView()

            } else if let usage {

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {

                    HStack {

                        Text(
                            "apifyaccountrow_usage"
                        )

                        Spacer()

                        Text(
                            String(
                                format:
                                    "$%.2f / $%.2f",
                                usage.usedUSD,
                                usage.maxUSD
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    ProgressView(
                        value:
                            usage.usageFraction
                    )

                    LabeledContent(
                        "apifyaccountrow_compute"
                    ) {

                        Text(
                            String(
                                format:
                                    "%.2f CU",
                                usage.computeUnits
                            )
                        )
                    }

                    LabeledContent(
                        "apifyaccountrow_data_transfer"
                    ) {

                        Text(
                            String(
                                format:
                                    "%.2f / %.2f GB",
                                usage.externalTransferGB,
                                usage.maxExternalTransferGB
                            )
                        )
                    }

                    LabeledContent(
                        "apifyaccountrow_ram"
                    ) {

                        Text(
                            String(
                                format:
                                    "%.1f / %.1f GB",
                                usage.actorMemoryGB,
                                usage.maxActorMemoryGB
                            )
                        )
                    }
                }

            } else if let errorMessage {

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !isActive {

                Button {

                    settings.setActive(
                        account
                    )

                } label: {

                    Label(
                        "apifyaccountrow_use_account",
                        systemImage:
                            "arrow.triangle.2.circlepath"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )

            } else {

                Label(
                    "apifyaccountrow_echo_using_token",
                    systemImage:
                        "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }
        }

        .padding(
            .vertical,
            6
        )

        .task {
            await loadUsage()
        }

        .refreshable {
            await loadUsage()
        }
    }

    private func loadUsage() async {

        loading = true
        errorMessage = nil

        do {

            usage =
                try await
                ApifyAccountUsageAPI
                    .load(
                        token:
                            account.token
                    )

        } catch {

            errorMessage =
                error.localizedDescription
        }

        loading = false
    }

    private func maskedToken(
        _ token: String
    ) -> String {

        guard token.count > 8 else {
            return "••••••••"
        }

        return
            "••••••••\(token.suffix(6))"
    }
}
