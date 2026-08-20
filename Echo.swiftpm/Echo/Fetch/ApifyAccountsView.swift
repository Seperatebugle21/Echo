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
                    "No Apify Accounts",
                    systemImage:
                        "person.crop.circle.badge.plus",
                    description:
                        Text(
                            "Add an API token to use Apify with Echo."
                        )
                )

            } else {

                ForEach(
                    settings.accounts
                ) { account in

                    ApifyAccountRow(
                        account: account
                    )
                }
                .onDelete {
                    offsets in

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
            "Apify Accounts"
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
