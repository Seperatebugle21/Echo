import SwiftUI

struct AddApifyAccountView: View {

    @Environment(\.dismiss)
    private var dismiss

    @State private var settings =
        ApifySettings.shared

    @State private var name = ""
    @State private var token = ""

    @State private var showToken =
        false

    var body: some View {

        NavigationStack {

            Form {

                Section(
                    "addapifyaccountview_account"
                ) {

                    TextField(
                        String(
                            localized:
                                "addapifyaccountview_account_name"
                        ),
                        text: $name
                    )

                    HStack {

                        if showToken {

                            TextField(
                                String(
                                    localized:
                                        "addapifyaccountview_api_token"
                                ),
                                text: $token
                            )
                            .textInputAutocapitalization(
                                .never
                            )
                            .autocorrectionDisabled()

                        } else {

                            SecureField(
                                String(
                                    localized:
                                        "addapifyaccountview_api_token"
                                ),
                                text: $token
                            )
                        }

                        Button {

                            showToken.toggle()

                        } label: {

                            Image(
                                systemName:
                                    showToken
                                    ? "eye.slash"
                                    : "eye"
                            )
                        }
                    }
                }
            }

            .navigationTitle(
                "addapifyaccountview_title"
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {

                    Button(
                        "addapifyaccountview_cancel"
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {

                    Button(
                        "addapifyaccountview_add"
                    ) {

                        settings.addAccount(
                            name: name,
                            token: token
                        )

                        dismiss()
                    }
                    .disabled(
                        token
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
            }
        }
    }
}
