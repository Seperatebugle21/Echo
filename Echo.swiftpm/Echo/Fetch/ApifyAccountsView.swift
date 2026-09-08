import SwiftUI

struct ApifyAccountsView: View {

    @State private var settings =
        ApifySettings.shared

    @State private var showAddAccount =
        false

    var body: some View {

        List {

            if settings.accounts.isEmpty {

                ContentUnavailableView(
                    "apifyaccountsview_empty_title",
                    systemImage:
                        "person.crop.circle.badge.plus",
                    description:
                        Text(
                            "apifyaccountsview_empty_description"
                        )
                )

            } else {

                ForEach(
                    settings.accounts
                ) { account in

                    Section {

                        ApifyAccountRow(
                            account: account
                        )
                    }
                }
                .onDelete { offsets in

                    for index in offsets {

                        let account =
                            settings.accounts[
                                index
                            ]

                        settings
                            .removeAccount(
                                account
                            )
                    }
                }
            }
        }

        .navigationTitle(
            "apifyaccountsview_title"
        )

        .toolbar {

            ToolbarItem(
                placement:
                    .topBarTrailing
            ) {

                Button {

                    showAddAccount = true

                } label: {

                    Image(
                        systemName: "plus"
                    )
                }
            }
        }

        .sheet(
            isPresented:
                $showAddAccount
        ) {

            AddApifyAccountView()
        }
    }
}
