import Foundation
import SwiftUI

struct YouTubeMusicTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: String?
    let thumbnailURL: URL?

    var videoURL: URL {
        URL(string: "https://music.youtube.com/watch?v=\(id)")!
    }
}

enum YouTubeMusicAPIError: LocalizedError {
    case invalidResponse
    case webConfigurationUnavailable
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "YouTube Music returned an invalid response."
        case .webConfigurationUnavailable:
            return "Could not load the YouTube Music web configuration."
        case .requestFailed(let statusCode):
            return "YouTube Music request failed (HTTP \(statusCode))."
        }
    }
}

actor YouTubeMusicAPI {
    static let shared = YouTubeMusicAPI()

    private struct WebConfiguration {
        let apiKey: String
        let clientVersion: String
    }

    private var cachedConfiguration: WebConfiguration?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        ]
        session = URLSession(configuration: config)
    }

    func searchSongs(query: String, maxResults: Int = 25) async throws -> [YouTubeMusicTrack] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var config = try await webConfiguration()

        do {
            return try await performSearch(
                query: text,
                maxResults: maxResults,
                configuration: config
            )
        } catch YouTubeMusicAPIError.requestFailed(let status)
            where status == 400 || status == 401 || status == 403 {

            cachedConfiguration = nil
            config = try await webConfiguration()

            return try await performSearch(
                query: text,
                maxResults: maxResults,
                configuration: config
            )
        }
    }

    private func performSearch(
        query: String,
        maxResults: Int,
        configuration: WebConfiguration
    ) async throws -> [YouTubeMusicTrack] {

        var components = URLComponents(
            string: "https://music.youtube.com/youtubei/v1/search"
        )!

        components.queryItems = [
            URLQueryItem(name: "key", value: configuration.apiKey),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]

        guard let url = components.url else {
            throw YouTubeMusicAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("67", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(configuration.clientVersion, forHTTPHeaderField: "X-Youtube-Client-Version")

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": configuration.clientVersion,
                    "hl": Locale.current.language.languageCode?.identifier ?? "en",
                    "gl": Locale.current.region?.identifier ?? "BE",
                    "utcOffsetMinutes": TimeZone.current.secondsFromGMT() / 60
                ]
            ],
            "query": query
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw YouTubeMusicAPIError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            throw YouTubeMusicAPIError.requestFailed(http.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data)
        let renderers = responsiveListRenderers(in: json)

        var tracks: [YouTubeMusicTrack] = []
        var seen = Set<String>()

        for renderer in renderers {
            guard let track = parseSong(renderer),
                  seen.insert(track.id).inserted
            else {
                continue
            }

            tracks.append(track)

            if tracks.count >= maxResults {
                break
            }
        }

        return tracks
    }

    private func webConfiguration() async throws -> WebConfiguration {
        if let cachedConfiguration {
            return cachedConfiguration
        }

        var request = URLRequest(
            url: URL(string: "https://music.youtube.com/")!
        )
        request.setValue(
            "text/html,application/xhtml+xml",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let html = String(data: data, encoding: .utf8)
        else {
            throw YouTubeMusicAPIError.webConfigurationUnavailable
        }

        guard let apiKey = regexCapture(
            #"\"INNERTUBE_API_KEY\"\s*:\s*\"([^\"]+)\""#,
            in: html
        ) else {
            throw YouTubeMusicAPIError.webConfigurationUnavailable
        }

        let version = regexCapture(
            #"\"INNERTUBE_CLIENT_VERSION\"\s*:\s*\"([^\"]+)\""#,
            in: html
        ) ?? "1.20260114.03.00"

        let config = WebConfiguration(
            apiKey: apiKey,
            clientVersion: version
        )

        cachedConfiguration = config
        return config
    }

    private func regexCapture(
        _ pattern: String,
        in text: String
    ) -> String? {

        guard let regex = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return nil
        }

        let range = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )

        guard let match = regex.firstMatch(
            in: text,
            range: range
        ),
              match.numberOfRanges > 1,
              let swiftRange = Range(
                match.range(at: 1),
                in: text
              )
        else {
            return nil
        }

        return String(text[swiftRange])
    }

    private func responsiveListRenderers(
        in object: Any
    ) -> [[String: Any]] {

        var result: [[String: Any]] = []

        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let renderer =
                    dict["musicResponsiveListItemRenderer"]
                    as? [String: Any]
                {
                    result.append(renderer)
                }

                for child in dict.values {
                    walk(child)
                }

            } else if let array = value as? [Any] {

                for child in array {
                    walk(child)
                }
            }
        }

        walk(object)
        return result
    }

    private func parseSong(
        _ renderer: [String: Any]
    ) -> YouTubeMusicTrack? {

        guard let videoID = findVideoID(in: renderer) else {
            return nil
        }

        let columns =
            renderer["flexColumns"] as? [[String: Any]] ?? []

        let titleRuns = runs(in: columns.first)

        guard let title =
                titleRuns.first?["text"] as? String,
              !title.isEmpty
        else {
            return nil
        }

        let metadataRuns =
            columns.dropFirst().flatMap {
                runs(in: $0)
            }

        var artist: String?
        var album: String?

        for run in metadataRuns {

            guard let value =
                    run["text"] as? String
            else {
                continue
            }

            let text =
                value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            guard
                !text.isEmpty,
                text != "•",
                !isDuration(text),
                !isYear(text)
            else {
                continue
            }

            let browse =
                browseID(in: run)

            if browse?.hasPrefix("MPRE") == true {

                if album == nil {
                    album = text
                }

            } else if
                artist == nil &&
                (
                    browse?.hasPrefix("UC") == true ||
                    browse?.hasPrefix("MPLA") == true
                )
            {
                artist = text
            }
        }

        if artist == nil {

            artist =
                metadataRuns
                    .compactMap {
                        $0["text"] as? String
                    }
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                    .first {
                        !$0.isEmpty &&
                        $0 != "•" &&
                        !isDuration($0) &&
                        !isYear($0) &&
                        $0.caseInsensitiveCompare("Song")
                            != .orderedSame
                    }
        }

        guard let artist,
              !artist.isEmpty
        else {
            return nil
        }

        let fixed =
            renderer["fixedColumns"]
            as? [[String: Any]] ?? []

        let texts =
            fixed
                .flatMap {
                    runs(in: $0)
                }
                .compactMap {
                    $0["text"] as? String
                }
            +
            metadataRuns
                .compactMap {
                    $0["text"] as? String
                }

        return YouTubeMusicTrack(
            id: videoID,
            title: title,
            artist: artist,
            album: album,
            duration:
                texts.first(
                    where: isDuration
                ),
            thumbnailURL:
                largestThumbnailURL(
                    in: renderer
                )
        )
    }

    private func runs(
        in column: [String: Any]?
    ) -> [[String: Any]] {

        guard
            let column,
            let renderer =
                column[
                    "musicResponsiveListItemFlexColumnRenderer"
                ] as? [String: Any],
            let text =
                renderer["text"] as? [String: Any],
            let runs =
                text["runs"] as? [[String: Any]]
        else {
            return []
        }

        return runs
    }

    private func browseID(
        in run: [String: Any]
    ) -> String? {

        let nav =
            run["navigationEndpoint"]
            as? [String: Any]

        let browse =
            nav?["browseEndpoint"]
            as? [String: Any]

        return browse?["browseId"] as? String
    }

    private func findVideoID(
        in object: Any
    ) -> String? {

        if let dict =
            object as? [String: Any]
        {
            if
                let watch =
                    dict["watchEndpoint"]
                    as? [String: Any],
                let id =
                    watch["videoId"] as? String
            {
                return id
            }

            if
                let data =
                    dict["playlistItemData"]
                    as? [String: Any],
                let id =
                    data["videoId"] as? String
            {
                return id
            }

            for child in dict.values {
                if let id =
                    findVideoID(in: child)
                {
                    return id
                }
            }

        } else if let array =
            object as? [Any]
        {
            for child in array {
                if let id =
                    findVideoID(in: child)
                {
                    return id
                }
            }
        }

        return nil
    }

    private func largestThumbnailURL(
        in object: Any
    ) -> URL? {

        var candidates:
            [(area: Int, url: URL)] = []

        func walk(_ value: Any) {

            if let dict =
                value as? [String: Any]
            {
                if let thumbs =
                    dict["thumbnails"]
                    as? [[String: Any]]
                {
                    for thumb in thumbs {

                        guard let raw =
                            thumb["url"] as? String
                        else {
                            continue
                        }

                        let value =
                            raw.hasPrefix("//")
                            ? "https:\(raw)"
                            : raw

                        guard let url =
                            URL(string: value)
                        else {
                            continue
                        }

                        let width =
                            thumb["width"] as? Int ?? 0

                        let height =
                            thumb["height"] as? Int ?? 0

                        candidates.append(
                            (
                                width * height,
                                url
                            )
                        )
                    }
                }

                for child in dict.values {
                    walk(child)
                }

            } else if let array =
                value as? [Any]
            {
                for child in array {
                    walk(child)
                }
            }
        }

        walk(object)

        return candidates
            .max {
                $0.area < $1.area
            }?
            .url
    }

    private func isDuration(
        _ text: String
    ) -> Bool {

        text.range(
            of: #"^\d{1,2}:\d{2}(?::\d{2})?$"#,
            options: .regularExpression
        ) != nil
    }

    private func isYear(
        _ text: String
    ) -> Bool {

        guard
            text.count == 4,
            let value = Int(text)
        else {
            return false
        }

        return (1900...2100)
            .contains(value)
    }
}

struct YouTubeMusicSearchView:
    View
{
    @State private var query =
        ""

    @State private var results:
        [YouTubeMusicTrack] = []

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
                    spacing: 10
                ) {

                    Image(
                        systemName:
                            "magnifyingglass"
                    )
                    .foregroundStyle(.secondary)

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
                    .submitLabel(.search)
                    .onSubmit {

                        Task {
                            await search()
                        }
                    }

                    if !query.isEmpty {

                        Button {

                            query = ""
                            results = []
                            errorMessage = nil

                        } label: {

                            Image(
                                systemName:
                                    "xmark.circle.fill"
                            )
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
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
                        alignment: .leading,
                        spacing: 6
                    ) {

                        Label(
                            "youtubemusicsearchview_youtube_music",
                            systemImage:
                                "music.note"
                        )
                        .font(.headline)

                        Text(
                            "youtubemusicsearchview_intro_description"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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

                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if !results.isEmpty {

                Section(
                    "youtubemusicsearchview_songs"
                ) {

                    ForEach(
                        results
                    ) { result in

                        Button {

                            selectedResult =
                                result

                        } label: {

                            HStack(
                                spacing: 12
                            ) {

                                AsyncImage(
                                    url:
                                        result.thumbnailURL
                                ) { image in

                                    image
                                        .resizable()
                                        .scaledToFill()

                                } placeholder: {

                                    RoundedRectangle(
                                        cornerRadius: 8
                                    )
                                    .fill(
                                        .secondary
                                            .opacity(0.12)
                                    )
                                }
                                .frame(
                                    width: 64,
                                    height: 64
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 8
                                    )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 4
                                ) {

                                    Text(
                                        result.title
                                    )
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                    Text(
                                        result.artist
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                    if let album =
                                        result.album,
                                       !album.isEmpty
                                    {
                                        HStack(
                                            spacing: 4
                                        ) {

                                            Text(album)

                                            if let duration =
                                                result.duration
                                            {
                                                Text("•")
                                                Text(duration)
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
        ) { result in

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

                    DispatchQueue.main.async {

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
        let text =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !text.isEmpty else {
            return
        }

        loading = true
        errorMessage = nil

        do {

            results =
                try await
                YouTubeMusicAPI.shared
                    .searchSongs(
                        query:
                            text,
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

            results = []

            errorMessage =
                error.localizedDescription
        }

        loading = false
    }
}
