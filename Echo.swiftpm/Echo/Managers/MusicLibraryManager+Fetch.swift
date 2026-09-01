import Foundation


extension MusicLibraryManager {

    // MARK: - Add Fetch Result

    @MainActor
    func addProcessedFetch(
        fileURL: URL,
        title: String,
        artist: String,
        album: String?,
        coverData: Data?,
        reuseExistingDuplicate: Bool = false
    ) -> Song? {

        let fileName =
            fileURL.lastPathComponent


        print(
            "Adding processed Fetch to library:",
            fileName
        )


        // =========================================
        // Exact same file already registered
        // =========================================

        if let existingIndex =
            songs.firstIndex(
                where: {
                    $0.fileName ==
                        fileName
                }
            ) {

            songs[existingIndex].title =
                title

            songs[existingIndex].artist =
                artist

            songs[existingIndex].album =
                album

            songs[existingIndex].coverData =
                coverData


            print(
                "Existing Fetch song metadata updated:",
                title,
                "-",
                artist
            )


            return songs[existingIndex]
        }


        // =========================================
        // Duplicate song in library
        //
        // Same title + same artist.
        //
        // Use the EXISTING Echo duplicate system
        // instead of silently adding another copy.
        // =========================================

        let duplicate =
            songs.first {
                song in

                normalizedDuplicateValue(
                    song.title
                )
                ==
                normalizedDuplicateValue(
                    title
                )
                &&
                normalizedDuplicateValue(
                    song.artist
                )
                ==
                normalizedDuplicateValue(
                    artist
                )
            }


        if let duplicate {

            if reuseExistingDuplicate {

                if duplicate.fileName != fileName {
                    try? FileManager.default
                        .removeItem(
                            at: fileURL
                        )
                }

                return duplicate
            }

            // =====================================
            // Apply previous "to all" choice
            // =====================================

            if applyToAllDuplicates,
               let lastDuplicateChoice {

                pendingDuplicateURL =
                    fileURL

                duplicateSongName =
                    title


                resolveDuplicate(
                    choice:
                        lastDuplicateChoice,
                    applyToAll:
                        true
                )


                return nil
            }


            // =====================================
            // Ask user
            // =====================================

            duplicateSongName =
                title

            pendingDuplicateURL =
                fileURL

            showDuplicateAlert =
                true


            print(
                "Fetch duplicate found:",
                title,
                "-",
                artist
            )


            return nil
        }


        // =========================================
        // New song
        // =========================================

        let song =
            Song(
                title:
                    title,

                artist:
                    artist,

                fileName:
                    fileName,

                album:
                    album,

                coverData:
                    coverData
            )


        songs.append(
            song
        )


        print(
            "Fetch successfully added:",
            song.title,
            "-",
            song.artist
        )

        return song
    }


    // MARK: - Duplicate Normalization

    private func normalizedDuplicateValue(
        _ value: String
    ) -> String {

        value
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ],
                locale:
                    .current
            )
            .replacingOccurrences(
                of:
                    "\\s+",
                with:
                    " ",
                options:
                    .regularExpression
            )
            .lowercased()
    }
}
