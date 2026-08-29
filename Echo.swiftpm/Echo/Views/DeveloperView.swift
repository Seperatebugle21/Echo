import SwiftUI

struct DeveloperView: View {

    @AppStorage("developerMaxDownloadChunks")
    private var maxDownloadChunks: Int = 4


    // MARK: - Storage

    @State private var totalStorage: Int64 = 0
    @State private var availableStorage: Int64 = 0
    @State private var echoStorage: Int64 = 0
    @State private var isLoadingStorage = false


    var body: some View {

        Form {

            // MARK: Downloads

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
                    "Higher values may improve download speed, but can also cause throttling or unstable downloads. Default is 4."
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


            // MARK: - Storage

            Section {

                // Storage overview

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {

                    HStack {

                        Text("iPhone Storage")

                        Spacer()

                        if isLoadingStorage {

                            ProgressView()
                                .controlSize(.small)
                        }
                    }


                    ProgressView(
                        value: usedStorageFraction
                    )


                    HStack {

                        Text(
                            formatBytes(
                                usedStorage
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)


                        Spacer()


                        Text(
                            "\(formatBytes(availableStorage)) free"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(
                    .vertical,
                    4
                )


                // Total storage

                storageRow(
                    title: "Total",
                    systemImage: "internaldrive",
                    value: totalStorage
                )


                // Used storage

                storageRow(
                    title: "Used",
                    systemImage: "chart.pie",
                    value: usedStorage
                )


                // Available storage

                storageRow(
                    title: "Available",
                    systemImage: "externaldrive.badge.checkmark",
                    value: availableStorage
                )


                // Echo storage

                storageRow(
                    title: "Echo",
                    systemImage: "waveform",
                    value: echoStorage
                )


                Button {

                    refreshStorage()

                } label: {

                    Label(
                        "Refresh Storage",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(
                    isLoadingStorage
                )

            } header: {

                Text("Storage")

            } footer: {

                Text(
                    "Echo storage includes downloaded music, app documents, caches and temporary files."
                )
            }
        }

        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)

        .task {

            refreshStorage()
        }
    }


    // MARK: - Storage Row

    private func storageRow(
        title: String,
        systemImage: String,
        value: Int64
    ) -> some View {

        HStack(
            spacing: 12
        ) {

            Image(
                systemName: systemImage
            )
            .foregroundStyle(.secondary)
            .frame(
                width: 24
            )


            Text(title)


            Spacer()


            Text(
                formatBytes(value)
            )
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }


    // MARK: - Storage Calculations

    private var usedStorage: Int64 {

        max(
            totalStorage - availableStorage,
            0
        )
    }


    private var usedStorageFraction: Double {

        guard totalStorage > 0 else {

            return 0
        }


        return min(
            max(
                Double(usedStorage)
                /
                Double(totalStorage),
                0
            ),
            1
        )
    }


    // MARK: - Refresh

    private func refreshStorage() {

        guard !isLoadingStorage else {

            return
        }


        isLoadingStorage = true


        Task.detached(
            priority: .utility
        ) {

            let deviceStorage =
                Self.deviceStorageInfo()


            let appStorage =
                Self.calculateEchoStorage()


            await MainActor.run {

                totalStorage =
                    deviceStorage.total

                availableStorage =
                    deviceStorage.available

                echoStorage =
                    appStorage

                isLoadingStorage =
                    false
            }
        }
    }


    // MARK: - Device Storage

    private nonisolated static func deviceStorageInfo()
        -> (
            total: Int64,
            available: Int64
        ) {

        let homeURL =
            URL(
                fileURLWithPath:
                    NSHomeDirectory()
            )


        do {

            let values =
                try homeURL
                    .resourceValues(
                        forKeys: [
                            .volumeTotalCapacityKey,
                            .volumeAvailableCapacityForImportantUsageKey
                        ]
                    )


            let total =
                Int64(
                    values.volumeTotalCapacity
                    ?? 0
                )


            let available =
                values
                    .volumeAvailableCapacityForImportantUsage
                ?? 0


            return (
                total,
                available
            )


        } catch {

            print(
                "Storage info error:",
                error
            )


            return (
                0,
                0
            )
        }
    }


    // MARK: - Echo Storage

    private nonisolated static func calculateEchoStorage()
        -> Int64 {

        let fileManager =
            FileManager.default


        let homeURL =
            URL(
                fileURLWithPath:
                    NSHomeDirectory(),
                isDirectory:
                    true
            )


        return directorySize(
            at: homeURL,
            fileManager: fileManager
        )
    }


    // MARK: - Directory Size

    private nonisolated static func directorySize(
        at directoryURL: URL,
        fileManager: FileManager
    ) -> Int64 {

        let keys:
            [URLResourceKey] = [

                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ]


        guard let enumerator =
            fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys:
                    keys,
                options: [
                    .skipsHiddenFiles
                ]
            )
        else {

            return 0
        }


        var totalSize:
            Int64 = 0


        for case let fileURL as URL
            in enumerator {

            autoreleasepool {

                do {

                    let values =
                        try fileURL
                            .resourceValues(
                                forKeys:
                                    Set(keys)
                            )


                    guard
                        values.isRegularFile
                            == true
                    else {

                        return
                    }


                    let size =
                        values.totalFileAllocatedSize
                        ??
                        values.fileAllocatedSize
                        ??
                        0


                    totalSize +=
                        Int64(size)


                } catch {

                    // Ignore individual files
                    // that cannot be inspected.
                }
            }
        }


        return totalSize
    }


    // MARK: - Formatting

    private func formatBytes(
        _ bytes: Int64
    ) -> String {

        guard bytes > 0 else {

            return "0 B"
        }


        return ByteCountFormatter
            .string(
                fromByteCount:
                    bytes,
                countStyle:
                    .file
            )
    }
}


#Preview {

    NavigationStack {

        DeveloperView()
    }
}
