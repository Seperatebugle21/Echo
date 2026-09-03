import Foundation
import SwiftUI

// MARK: - YouTube Music Result Model

struct YouTubeMusicTrack: Identifiable, Hashable {

    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: String?
    let thumbnailURL: URL?

    var videoURL: URL {
        URL(
            string:
                "https://music.youtube.com/watch?v=\(id)"
        )!
    }
}


// MARK: - Errors

enum YouTubeMusicAPIError:
    LocalizedError
{
    case invalidURL
    case invalidResponse
    case requestFailed(Int)
    case invalidJSON

    var errorDescription: String? {

        switch self {

        case .invalidURL:
            return "Could not build the YouTube Music request."

        case .invalidResponse:
            return "YouTube Music returned an invalid response."

        case .requestFailed(let statusCode):
            return "YouTube Music request failed (HTTP \(statusCode))."

        case .invalidJSON:
            return "Echo could not process the YouTube Music response."
        }
    }
}


// MARK: - Signed-out YouTube Music API

actor YouTubeMusicAPI {

    static let shared =
        YouTubeMusicAPI()


    /*
     Public WEB_REMIX InnerTube key.

     This is the same public web-client key used by current
     signed-out ytmusicapi-style requests. It is NOT a user
     credential and does not require a Google/YouTube login.
     */
    private let apiKey =
        "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"


    /*
     YouTube Music "Songs" search filter.

     This keeps the response focused on actual music tracks
     instead of ordinary YouTube videos, channels, etc.
     */
    private let songsSearchParams =
        "EgWKAQIIAWoMEA4QChADEAQQCRAF"


    private let session:
        URLSession


    private init() {

        let configuration =
            URLSessionConfiguration.ephemeral


        configuration.timeoutIntervalForRequest =
            20


        configuration.timeoutIntervalForResource =
            30


        configuration.httpAdditionalHeaders =
            [

                "Accept":
                    "*/*",

                "Accept-Language":
                    "en-US,en;q=0.9",

                "User-Agent":
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:88.0) Gecko/20100101 Firefox/88.0"
            ]


        session =
            URLSession(
                configuration:
                    configuration
            )
    }


    // MARK: Search Songs

    func searchSongs(
        query: String,
        maxResults: Int = 25
    ) async throws
        -> [YouTubeMusicTrack]
    {

        let cleaned =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard !cleaned.isEmpty else {

            return []
        }


        /*
         ytmusicapi currently builds WEB_REMIX versions as:
         1.YYYYMMDD.01.00

         We try today first, then yesterday, then a stable
         fallback known to work with the WEB_REMIX request shape.
         */
        let versions =
            clientVersionsToTry()


        var lastStatus:
            Int?


        for version in versions {

            do {

                return try await
                    performSearch(
                        query:
                            cleaned,

                        maxResults:
                            maxResults,

                        clientVersion:
                            version
                    )

            } catch
                YouTubeMusicAPIError
                    .requestFailed(
                        let status
                    )
            {

                lastStatus =
                    status


                /*
                 A rejected client version usually results in
                 400 or 403. Try the next version.
                 */
                if
                    status == 400 ||
                    status == 403
                {

                    continue
                }


                throw
                    YouTubeMusicAPIError
                        .requestFailed(
                            status
                        )
            }
        }


        if let lastStatus {

            throw
                YouTubeMusicAPIError
                    .requestFailed(
                        lastStatus
                    )
        }


        throw
            YouTubeMusicAPIError
                .invalidResponse
    }


    // MARK: Perform Search

    private func performSearch(
        query: String,
        maxResults: Int,
        clientVersion: String
    ) async throws
        -> [YouTubeMusicTrack]
    {

        var components =
            URLComponents(
                string:
                    "https://music.youtube.com/youtubei/v1/search"
            )


        components?.queryItems =
            [

                URLQueryItem(
                    name:
                        "alt",
                    value:
                        "json"
                ),

                URLQueryItem(
                    name:
                        "key",
                    value:
                        apiKey
                ),

                URLQueryItem(
                    name:
                        "prettyPrint",
                    value:
                        "false"
                )
            ]


        guard let url =
            components?.url
        else {

            throw
                YouTubeMusicAPIError
                    .invalidURL
        }


        var request =
            URLRequest(
                url:
                    url
            )


        request.httpMethod =
            "POST"


        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )


        request.setValue(
            "https://music.youtube.com",
            forHTTPHeaderField:
                "Origin"
        )


        request.setValue(
            "https://music.youtube.com/",
            forHTTPHeaderField:
                "Referer"
        )


        request.setValue(
            "67",
            forHTTPHeaderField:
                "X-YouTube-Client-Name"
        )


        request.setValue(
            clientVersion,
            forHTTPHeaderField:
                "X-YouTube-Client-Version"
        )


        let body:
            [String: Any] =
            [

                "context":
                    [

                        "client":
                            [

                                "clientName":
                                    "WEB_REMIX",

                                "clientVersion":
                                    clientVersion,

                                /*
                                 Keep hl = en for the request itself.
                                 Signed-out filtered searches have
                                 occasionally returned empty result
                                 shelves for some locales.
                                 */
                                "hl":
                                    "en",

                                "gl":
                                    "BE",

                                "utcOffsetMinutes":
                                    TimeZone
                                        .current
                                        .secondsFromGMT()
                                    /
                                    60
                            ],

                        "user":
                            [:]
                    ],

                "query":
                    query,

                "params":
                    songsSearchParams
            ]


        request.httpBody =
            try JSONSerialization
                .data(
                    withJSONObject:
                        body
                )


        let (
            data,
            response
        ) =
            try await
            session.data(
                for:
                    request
            )


        guard let http =
            response
                as?
                HTTPURLResponse
        else {

            throw
                YouTubeMusicAPIError
                    .invalidResponse
        }


        guard 200..<300 ~=
            http.statusCode
        else {

            throw
                YouTubeMusicAPIError
                    .requestFailed(
                        http.statusCode
                    )
        }


        let root: Any


        do {

            root =
                try JSONSerialization
                    .jsonObject(
                        with:
                            data
                    )

        } catch {

            throw
                YouTubeMusicAPIError
                    .invalidJSON
        }


        let renderers =
            responsiveListRenderers(
                in:
                    root
            )


        var results:
            [YouTubeMusicTrack] =
            []


        var seen =
            Set<String>()


        for renderer in renderers {

            guard
                let track =
                    parseSong(
                        renderer
                    ),

                seen
                    .insert(
                        track.id
                    )
                    .inserted

            else {

                continue
            }


            results.append(
                track
            )


            if results.count >=
                maxResults
            {

                break
            }
        }


        return results
    }


    // MARK: Client Versions

    private func clientVersionsToTry()
        -> [String]
    {

        let formatter =
            DateFormatter()


        formatter.locale =
            Locale(
                identifier:
                    "en_US_POSIX"
            )


        formatter.timeZone =
            TimeZone(
                secondsFromGMT:
                    0
            )


        formatter.dateFormat =
            "yyyyMMdd"


        let now =
            Date()


        let today =
            formatter.string(
                from:
                    now
            )


        let yesterdayDate =
            Calendar(
                identifier:
                    .gregorian
            )
            .date(
                byAdding:
                    .day,
                value:
                    -1,
                to:
                    now
            )
            ??
            now


        let yesterday =
            formatter.string(
                from:
                    yesterdayDate
            )


        return
            [

                "1.\(today).01.00",

                "1.\(yesterday).01.00",

                /*
                 Conservative fallback. The response structure
                 used by search is backward compatible across
                 many WEB_REMIX versions.
                 */
                "1.20231204.01.00"
            ]
    }


    // MARK: Find Song Renderers

    private func responsiveListRenderers(
        in object: Any
    ) -> [[String: Any]]
    {

        var found:
            [[String: Any]] =
            []


        func walk(
            _ value: Any
        ) {

            if let dictionary =
                value
                    as?
                    [String: Any]
            {

                if let renderer =
                    dictionary[
                        "musicResponsiveListItemRenderer"
                    ]
                    as?
                    [String: Any]
                {

                    found.append(
                        renderer
                    )
                }


                for child in
                    dictionary.values
                {

                    walk(
                        child
                    )
                }

            } else if let array =
                value
                    as?
                    [Any]
            {

                for child in
                    array
                {

                    walk(
                        child
                    )
                }
            }
        }


        walk(
            object
        )


        return found
    }


    // MARK: Parse Song

    private func parseSong(
        _ renderer: [String: Any]
    ) -> YouTubeMusicTrack?
    {

        guard let videoID =
            findVideoID(
                in:
                    renderer
            )
        else {

            return nil
        }


        let flexColumns =
            renderer[
                "flexColumns"
            ]
            as?
            [[String: Any]]
            ??
            []


        guard
            let firstColumn =
                flexColumns.first
        else {

            return nil
        }


        let titleRuns =
            flexRuns(
                in:
                    firstColumn
            )


        guard
            let rawTitle =
                titleRuns
                    .first?[
                        "text"
                    ]
                    as?
                    String
        else {

            return nil
        }


        let title =
            rawTitle
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard !title.isEmpty else {

            return nil
        }


        let metadataRuns =
            flexColumns
                .dropFirst()
                .flatMap {

                    flexRuns(
                        in:
                            $0
                    )
                }


        var artist:
            String?


        var album:
            String?


        for run in metadataRuns {

            guard let rawText =
                run[
                    "text"
                ]
                as?
                String
            else {

                continue
            }


            let text =
                rawText
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )


            guard isUsefulMetadataText(
                text
            ) else {

                continue
            }


            let pageType =
                musicPageType(
                    in:
                        run
                )


            if pageType ==
                "MUSIC_PAGE_TYPE_ARTIST"
            {

                if artist == nil {

                    artist =
                        text
                }


                continue
            }


            if pageType ==
                "MUSIC_PAGE_TYPE_ALBUM"
            {

                if album == nil {

                    album =
                        text
                }


                continue
            }


            let browseID =
                browseID(
                    in:
                        run
                )


            if
                artist == nil,
                (
                    browseID?
                        .hasPrefix(
                            "UC"
                        )
                    ==
                    true
                    ||
                    browseID?
                        .hasPrefix(
                            "MPLA"
                        )
                    ==
                    true
                )
            {

                artist =
                    text


                continue
            }


            if
                album == nil,
                browseID?
                    .hasPrefix(
                        "MPRE"
                    )
                ==
                true
            {

                album =
                    text
            }
        }


        /*
         Fallback: filtered "Songs" rows normally expose artist
         navigation, but plain-text artist metadata is possible.
         In that case take the first useful metadata value that
         is not obviously an album/year/duration/type label.
         */
        if artist == nil {

            artist =
                metadataRuns
                    .compactMap {

                        $0[
                            "text"
                        ]
                        as?
                        String
                    }
                    .map {

                        $0
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                    }
                    .first {

                        isUsefulMetadataText(
                            $0
                        )
                        &&
                        !isResultTypeLabel(
                            $0
                        )
                    }
        }


        guard
            let artist,
            !artist.isEmpty
        else {

            return nil
        }


        let fixedColumns =
            renderer[
                "fixedColumns"
            ]
            as?
            [[String: Any]]
            ??
            []


        let fixedTexts =
            fixedColumns
                .flatMap {

                    fixedRuns(
                        in:
                            $0
                    )
                }
                .compactMap {

                    $0[
                        "text"
                    ]
                    as?
                    String
                }


        let metadataTexts =
            metadataRuns
                .compactMap {

                    $0[
                        "text"
                    ]
                    as?
                    String
                }


        let duration =
            (
                fixedTexts
                +
                metadataTexts
            )
            .map {

                $0
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
            }
            .first(
                where:
                    isDuration
            )


        return
            YouTubeMusicTrack(

                id:
                    videoID,

                title:
                    title,

                artist:
                    artist,

                album:
                    album,

                duration:
                    duration,

                thumbnailURL:
                    largestThumbnailURL(
                        in:
                            renderer
                    )
            )
    }


    // MARK: Text Runs

    private func flexRuns(
        in column: [String: Any]
    ) -> [[String: Any]]
    {

        guard
            let renderer =
                column[
                    "musicResponsiveListItemFlexColumnRenderer"
                ]
                as?
                [String: Any],

            let text =
                renderer[
                    "text"
                ]
                as?
                [String: Any],

            let runs =
                text[
                    "runs"
                ]
                as?
                [[String: Any]]
        else {

            return []
        }


        return runs
    }


    private func fixedRuns(
        in column: [String: Any]
    ) -> [[String: Any]]
    {

        guard
            let renderer =
                column[
                    "musicResponsiveListItemFixedColumnRenderer"
                ]
                as?
                [String: Any],

            let text =
                renderer[
                    "text"
                ]
                as?
                [String: Any],

            let runs =
                text[
                    "runs"
                ]
                as?
                [[String: Any]]
        else {

            return []
        }


        return runs
    }


    // MARK: Navigation Metadata

    private func browseID(
        in run: [String: Any]
    ) -> String?
    {

        let navigation =
            run[
                "navigationEndpoint"
            ]
            as?
            [String: Any]


        let browse =
            navigation?[
                "browseEndpoint"
            ]
            as?
            [String: Any]


        return
            browse?[
                "browseId"
            ]
            as?
            String
    }


    private func musicPageType(
        in run: [String: Any]
    ) -> String?
    {

        guard
            let navigation =
                run[
                    "navigationEndpoint"
                ]
                as?
                [String: Any],

            let browse =
                navigation[
                    "browseEndpoint"
                ]
                as?
                [String: Any],

            let supported =
                browse[
                    "browseEndpointContextSupportedConfigs"
                ]
                as?
                [String: Any],

            let musicConfig =
                supported[
                    "browseEndpointContextMusicConfig"
                ]
                as?
                [String: Any]
        else {

            return nil
        }


        return
            musicConfig[
                "pageType"
            ]
            as?
            String
    }


    // MARK: Video ID

    private func findVideoID(
        in object: Any
    ) -> String?
    {

        if let dictionary =
            object
                as?
                [String: Any]
        {

            if
                let data =
                    dictionary[
                        "playlistItemData"
                    ]
                    as?
                    [String: Any],

                let id =
                    data[
                        "videoId"
                    ]
                    as?
                    String,

                !id.isEmpty
            {

                return id
            }


            if
                let watch =
                    dictionary[
                        "watchEndpoint"
                    ]
                    as?
                    [String: Any],

                let id =
                    watch[
                        "videoId"
                    ]
                    as?
                    String,

                !id.isEmpty
            {

                return id
            }


            for child in
                dictionary.values
            {

                if let id =
                    findVideoID(
                        in:
                            child
                    )
                {

                    return id
                }
            }

        } else if let array =
            object
                as?
                [Any]
        {

            for child in array {

                if let id =
                    findVideoID(
                        in:
                            child
                    )
                {

                    return id
                }
            }
        }


        return nil
    }


    // MARK: Artwork

    private func largestThumbnailURL(
        in object: Any
    ) -> URL?
    {

        var candidates:
            [(area: Int, url: URL)] =
            []


        func walk(
            _ value: Any
        ) {

            if let dictionary =
                value
                    as?
                    [String: Any]
            {

                if let thumbnails =
                    dictionary[
                        "thumbnails"
                    ]
                    as?
                    [[String: Any]]
                {

                    for thumbnail in
                        thumbnails
                    {

                        guard let rawURL =
                            thumbnail[
                                "url"
                            ]
                            as?
                            String
                        else {

                            continue
                        }


                        let normalized =
                            rawURL.hasPrefix(
                                "//"
                            )
                            ?
                            "https:\(rawURL)"
                            :
                            rawURL


                        guard let url =
                            URL(
                                string:
                                    normalized
                            )
                        else {

                            continue
                        }


                        let width =
                            thumbnail[
                                "width"
                            ]
                            as?
                            Int
                            ??
                            0


                        let height =
                            thumbnail[
                                "height"
                            ]
                            as?
                            Int
                            ??
                            0


                        candidates.append(
                            (
                                width * height,
                                url
                            )
                        )
                    }
                }


                for child in
                    dictionary.values
                {

                    walk(
                        child
                    )
                }

            } else if let array =
                value
                    as?
                    [Any]
            {

                for child in
                    array
                {

                    walk(
                        child
                    )
                }
            }
        }


        walk(
            object
        )


        return
            candidates
                .max(
                    by: {
                        $0.area < $1.area
                    }
                )?
                .url
    }


    // MARK: Helpers

    private func isUsefulMetadataText(
        _ text: String
    ) -> Bool
    {

        !text.isEmpty
        &&
        text != "•"
        &&
        text != " · "
        &&
        !isDuration(
            text
        )
        &&
        !isYear(
            text
        )
    }


    private func isResultTypeLabel(
        _ text: String
    ) -> Bool
    {

        let lower =
            text.lowercased()


        return
            lower == "song"
            ||
            lower == "songs"
            ||
            lower == "video"
            ||
            lower == "videos"
    }


    private func isDuration(
        _ text: String
    ) -> Bool
    {

        text.range(
            of:
                #"^\d{1,2}:\d{2}(?::\d{2})?$"#,
            options:
                .regularExpression
        )
        !=
        nil
    }


    private func isYear(
        _ text: String
    ) -> Bool
    {

        guard
            text.count == 4,

            let value =
                Int(
                    text
                )
        else {

            return false
        }


        return
            (1900...2100)
                .contains(
                    value
                )
    }
}


// MARK: - View

struct YouTubeMusicSearchView:
    View
{

    @State private var query =
        ""


    @State private var results:
        [YouTubeMusicTrack] =
        []


    @State private var loading =
        false


    @State private var errorMessage:
        String?


    @State private var selectedResult:
        YouTubeMusicTrack?


    var body: some View {

        List {

            Section {

                HStack(
                    spacing:
                        10
                ) {

                    Image(
                        systemName:
                            "magnifyingglass"
                    )
                    .foregroundStyle(
                        .secondary
                    )


                    TextField(
                        String(
                            localized:
                                "youtubemusicsearchview_placeholder"
                        ),
                        text:
                            $query
                    )
                    .textInputAutocapitalization(
                        .never
                    )
                    .autocorrectionDisabled()
                    .submitLabel(
                        .search
                    )
                    .onSubmit {

                        Task {

                            await search()
                        }
                    }


                    if !query.isEmpty {

                        Button {

                            query =
                                ""

                            results =
                                []

                            errorMessage =
                                nil

                        } label: {

                            Image(
                                systemName:
                                    "xmark.circle.fill"
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                        .buttonStyle(
                            .plain
                        )
                    }
                }
            }


            if
                results.isEmpty,
                !loading,
                errorMessage == nil
            {

                Section {

                    VStack(
                        alignment:
                            .leading,
                        spacing:
                            6
                    ) {

                        Label(
                            "youtubemusicsearchview_youtube_music",
                            systemImage:
                                "music.note"
                        )
                        .font(
                            .headline
                        )


                        Text(
                            "youtubemusicsearchview_intro_description"
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .padding(
                        .vertical,
                        4
                    )
                }
            }


            if loading {

                Section {

                    HStack {

                        Spacer()

                        ProgressView()

                        Spacer()
                    }
                }
            }


            if let errorMessage {

                Section {

                    Text(
                        errorMessage
                    )
                    .foregroundStyle(
                        .red
                    )
                    .font(
                        .caption
                    )
                }
            }


            if !results.isEmpty {

                Section(
                    "youtubemusicsearchview_songs"
                ) {

                    ForEach(
                        results
                    ) {
                        result in


                        Button {

                            selectedResult =
                                result

                        } label: {

                            HStack(
                                spacing:
                                    12
                            ) {

                                AsyncImage(
                                    url:
                                        result
                                            .thumbnailURL
                                ) {
                                    image in


                                    image
                                        .resizable()
                                        .scaledToFill()

                                } placeholder: {

                                    RoundedRectangle(
                                        cornerRadius:
                                            8
                                    )
                                    .fill(
                                        .secondary
                                            .opacity(
                                                0.12
                                            )
                                    )
                                }
                                .frame(
                                    width:
                                        64,
                                    height:
                                        64
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            8
                                    )
                                )


                                VStack(
                                    alignment:
                                        .leading,
                                    spacing:
                                        4
                                ) {

                                    Text(
                                        result.title
                                    )
                                    .font(
                                        .headline
                                    )
                                    .foregroundStyle(
                                        .primary
                                    )
                                    .lineLimit(
                                        2
                                    )


                                    Text(
                                        result.artist
                                    )
                                    .font(
                                        .caption
                                    )
                                    .foregroundStyle(
                                        .secondary
                                    )
                                    .lineLimit(
                                        1
                                    )


                                    if
                                        let album =
                                            result.album,
                                        !album.isEmpty
                                    {

                                        HStack(
                                            spacing:
                                                4
                                        ) {

                                            Text(
                                                album
                                            )


                                            if let duration =
                                                result.duration
                                            {

                                                Text(
                                                    "•"
                                                )


                                                Text(
                                                    duration
                                                )
                                            }
                                        }
                                        .font(
                                            .caption2
                                        )
                                        .foregroundStyle(
                                            .tertiary
                                        )
                                        .lineLimit(
                                            1
                                        )
                                    }
                                }


                                Spacer()


                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(
                                    .caption
                                )
                                .foregroundStyle(
                                    .tertiary
                                )
                            }
                            .contentShape(
                                Rectangle()
                            )
                        }
                        .buttonStyle(
                            .plain
                        )
                    }
                }
            }
        }


        .navigationTitle(
            "youtubemusicsearchview_title"
        )


        .navigationBarTitleDisplayMode(
            .inline
        )


        .sheet(
            item:
                $selectedResult
        ) {
            result in


            YouTubeMusicResultView(
                result:
                    result,

                onClose: {

                    selectedResult =
                        nil
                },

                onViewDownloads: {

                    selectedResult =
                        nil


                    DispatchQueue
                        .main
                        .async {

                            NotificationCenter
                                .default
                                .post(
                                    name:
                                        .echoOpenFetchDownloads,
                                    object:
                                        nil
                                )
                        }
                }
            )
        }
    }


    private func search()
        async
    {

        let cleaned =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard !cleaned.isEmpty else {

            return
        }


        loading =
            true


        errorMessage =
            nil


        do {

            results =
                try await
                YouTubeMusicAPI
                    .shared
                    .searchSongs(
                        query:
                            cleaned,

                        maxResults:
                            25
                    )


            if results.isEmpty {

                errorMessage =
                    String(
                        localized:
                            "youtubemusicsearchview_no_music_found"
                    )
            }

        } catch {

            results =
                []


            errorMessage =
                error
                    .localizedDescription
        }


        loading =
            false
    }
}
