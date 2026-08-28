import Foundation


extension MusicLibraryManager {

    // MARK: - Add Fetch Result

    @MainActor
    func addProcessedFetch(
        fileURL: URL,
        title: String,
        artist: String,
        album: String?,
        coverData: Data?
    ) {

        let fileName =
            fileURL.lastPathComponent


        print(
            "Adding processed Fetch to library:",
            fileName
        )


        // =========================================
        // Already exists?
        //
        // Bijvoorbeeld wanneer een documents sync
        // het bestand net vóór ons al gevonden heeft.
        //
        // Dan corrigeren we de metadata in plaats
        // van nog een Song te maken.
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


            return
        }


        // =========================================
        // Add directly
        //
        // We already KNOW all metadata from Spotify.
        //
        // Dus niet:
        //
        // MP3 -> AVAsset -> metadata gokken
        //
        // maar:
        //
        // Spotify -> Song
        // =========================================

        let song =
            Song(
                title: title,
                artist: artist,
                fileName: fileName,
                album: album,
                coverData: coverData
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
    }
}
