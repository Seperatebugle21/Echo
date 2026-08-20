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

    private init() {}

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

        accessToken = token.accessToken
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
