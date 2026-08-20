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

                Section("Account") {

                    TextField(
                        "Account name",
                        text: $name
                    )


                    HStack {

                        if showToken {

                            TextField(
                                "API token",
                                text: $token
                            )
                            .textInputAutocapitalization(
                                .never
                            )
                            .autocorrectionDisabled()

                        } else {

                            SecureField(
                                "API token",
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
                "Add Apify Account"
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                }


                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {

                    Button("Add") {

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
