import Foundation
import CryptoKit
import UIKit

@MainActor
@Observable
final class SpotifyManager {

    static let shared = SpotifyManager()

    private(set) var isConnected = false
    private(set) var accessToken: String?

    private let clientID = "6fb432cf1a8f4454875812a2213d34c5"
    private let redirectURI = "echo-spotify-login://callback"

    private var codeVerifier: String?
    private var state: String?

    private let accessTokenKey =
    "echo.spotify.accessToken"

    private let refreshTokenKey =
    "echo.spotify.refreshToken"

    private let expirationKey =
    "echo.spotify.expiration"


    private(set) var refreshToken: String?
    private var tokenExpiration: Date?
    
    private init() {
        restoreSession()
    }

    func connect() {

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(
            from: verifier
        )

        let state = generateRandomString(
            length: 32
        )

        codeVerifier = verifier
        self.state = state

        var components = URLComponents(
            string:
                "https://accounts.spotify.com/authorize"
        )!

        components.queryItems = [
            URLQueryItem(
                name: "client_id",
                value: clientID
            ),
            URLQueryItem(
                name: "response_type",
                value: "code"
            ),
            URLQueryItem(
                name: "redirect_uri",
                value: redirectURI
            ),
            URLQueryItem(
                name: "code_challenge_method",
                value: "S256"
            ),
            URLQueryItem(
                name: "code_challenge",
                value: challenge
            ),
            URLQueryItem(
                name: "state",
                value: state
            ),
            URLQueryItem(
                name: "scope",
                value: [
                    "user-library-read",
                    "playlist-read-private",
                    "playlist-read-collaborative",
                    "user-read-private"
                ].joined(separator: " ")
            )
        ]

        guard let url = components.url else {
            return
        }

        UIApplication.shared.open(url)
    }



    func disconnect() {
    clearSession()
}



    

    func handleCallback(
        url: URL
    ) async {

        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {
            return
        }

        let query = components.queryItems ?? []

        if let error = query.first(
            where: { $0.name == "error" }
        )?.value {

            print(
                "Spotify authorization failed: \(error)"
            )

            return
        }

        guard
            let returnedState = query.first(
                where: { $0.name == "state" }
            )?.value,
            returnedState == state
        else {
            print("Spotify state mismatch")
            return
        }

        guard
            let code = query.first(
                where: { $0.name == "code" }
            )?.value,
            let verifier = codeVerifier
        else {
            return
        }

        do {
            try await exchangeCode(
                code,
                verifier: verifier
            )
        } catch {
            print(
                "Spotify token exchange failed:",
                error
            )
        }
    }

    func validAccessToken() async throws -> String {

    if let accessToken,
       let expiration = tokenExpiration,
       expiration >
        Date().addingTimeInterval(60) {

        return accessToken
    }


    try await refreshAccessToken()


    guard let accessToken else {
        throw SpotifyError.authenticationFailed
    }


    return accessToken
}


    private func clearSession() {

    accessToken = nil
    refreshToken = nil
    tokenExpiration = nil

    isConnected = false


    KeychainHelper.delete(
        accessTokenKey
    )

    KeychainHelper.delete(
        refreshTokenKey
    )

    KeychainHelper.delete(
        expirationKey
    )
}

    private func refreshAccessToken()
async throws {

    guard let refreshToken else {

        isConnected = false

        throw SpotifyError
            .authenticationFailed
    }


    let url = URL(
        string:
            "https://accounts.spotify.com/api/token"
    )!


    var request =
        URLRequest(url: url)


    request.httpMethod = "POST"


    request.setValue(
        "application/x-www-form-urlencoded",
        forHTTPHeaderField:
            "Content-Type"
    )


    var components =
        URLComponents()


    components.queryItems = [

        URLQueryItem(
            name: "grant_type",
            value: "refresh_token"
        ),

        URLQueryItem(
            name: "refresh_token",
            value: refreshToken
        ),

        URLQueryItem(
            name: "client_id",
            value: clientID
        )
    ]


    request.httpBody =
        components
            .percentEncodedQuery?
            .data(using: .utf8)


    let (data, response) =
        try await URLSession.shared
            .data(for: request)


    guard let http =
        response as? HTTPURLResponse
    else {
        throw SpotifyError
            .authenticationFailed
    }


    if http.statusCode == 400 {

        if let object =
            try? JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any],

           let error =
            object["error"] as? String,

           error == "invalid_grant" {

            clearSession()

            throw SpotifyError
                .authenticationFailed
        }
    }


    guard http.statusCode == 200 else {
        throw SpotifyError
            .authenticationFailed
    }


    let token =
        try JSONDecoder().decode(
            SpotifyTokenResponse.self,
            from: data
        )


    saveTokenResponse(token)
}

    private func restoreSession() {

    accessToken =
        KeychainHelper.read(
            accessTokenKey
        )

    refreshToken =
        KeychainHelper.read(
            refreshTokenKey
        )

    if let expirationString =
        KeychainHelper.read(
            expirationKey
        ),
       let timestamp =
        Double(expirationString) {

        tokenExpiration =
            Date(
                timeIntervalSince1970:
                    timestamp
            )
    }

    if refreshToken != nil {
        isConnected = true
    }
}

    private func exchangeCode(
        _ code: String,
        verifier: String
    ) async throws {

        let url = URL(
            string:
                "https://accounts.spotify.com/api/token"
        )!

        var request = URLRequest(
            url: url
        )

        request.httpMethod = "POST"

        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        var components =
            URLComponents()

        components.queryItems = [
            URLQueryItem(
                name: "client_id",
                value: clientID
            ),
            URLQueryItem(
                name: "grant_type",
                value: "authorization_code"
            ),
            URLQueryItem(
                name: "code",
                value: code
            ),
            URLQueryItem(
                name: "redirect_uri",
                value: redirectURI
            ),
            URLQueryItem(
                name: "code_verifier",
                value: verifier
            )
        ]

        request.httpBody =
            components
                .percentEncodedQuery?
                .data(using: .utf8)

        let (
            data,
            response
        ) = try await URLSession.shared.data(
            for: request
        )

        guard
            let http =
                response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            throw SpotifyError.authenticationFailed
        }

        let token =
            try JSONDecoder().decode(
                SpotifyTokenResponse.self,
                from: data
            )

        saveTokenResponse(token)
    }

    private func saveTokenResponse(
    _ token: SpotifyTokenResponse
) {

    accessToken =
        token.accessToken

    KeychainHelper.save(
        token.accessToken,
        for: accessTokenKey
    )


    // Spotify geeft niet bij iedere refresh
    // per se een nieuwe refresh token.

    if let newRefreshToken =
        token.refreshToken {

        refreshToken =
            newRefreshToken

        KeychainHelper.save(
            newRefreshToken,
            for: refreshTokenKey
        )
    }


    let expiration =
        Date().addingTimeInterval(
            TimeInterval(token.expiresIn)
        )

    tokenExpiration =
        expiration

    KeychainHelper.save(
        String(
            expiration.timeIntervalSince1970
        ),
        for: expirationKey
    )


    isConnected = true
}

    private func generateCodeVerifier() -> String {
        generateRandomString(length: 64)
    }

    private func generateCodeChallenge(
        from verifier: String
    ) -> String {

        let data = Data(
            verifier.utf8
        )

        let hash = SHA256.hash(
            data: data
        )

        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(
                of: "=",
                with: ""
            )
            .replacingOccurrences(
                of: "+",
                with: "-"
            )
            .replacingOccurrences(
                of: "/",
                with: "_"
            )
    }

    private func generateRandomString(
        length: Int
    ) -> String {

        let characters =
            Array(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
            )

        return String(
            (0..<length).map { _ in
                characters.randomElement()!
            }
        )
    }
}

struct SpotifyTokenResponse: Decodable {

    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

enum SpotifyError: Error {
    case authenticationFailed
}
