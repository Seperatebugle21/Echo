import SwiftUI

struct DeveloperView: View {

    @AppStorage("developerMaxDownloadChunks")
    private var maxDownloadChunks: Int = 4


    var body: some View {

        Form {

            Section {
                
                Picker(
                    "Max Download Chunks",
                    selection: $maxDownloadChunks
                ) {

                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("6").tag(6)
                    Text("8").tag(8)
                    Text("10").tag(10)
                    Text("12").tag(12)
                    Text("16").tag(16)
                }

            } header: {

                Text("Downloads")

            } footer: {

                Text(
                    "Higher values may improve download speed, but can also cause throttling or unstable downloads. Default is 6."
                )
            }


            Section {

                HStack {

                    Text("Current value")

                    Spacer()

                    Text("\(maxDownloadChunks)")
                        .foregroundStyle(.secondary)
                }


                Button("Reset to Default") {

                    maxDownloadChunks = 4
                }
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }
}


#Preview {

    NavigationStack {

        DeveloperView()
    }
}
