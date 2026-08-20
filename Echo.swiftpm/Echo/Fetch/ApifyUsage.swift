import Foundation

struct ApifyUsageInfo {
    let usedUSD: Double
    let maxUSD: Double

    let actorComputeUnits: Double
    let externalTransferGB: Double
    let actorMemoryGB: Double

    var usageFraction: Double {
        guard maxUSD > 0 else { return 0 }
        return min(usedUSD / maxUSD, 1)
    }
}

enum ApifyUsageError: LocalizedError {
    case missingToken
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Apify token ontbreekt."
        case .invalidResponse:
            return "Apify usage kon niet worden gelezen."
        case .requestFailed(let code):
            return "Apify usage request mislukt (\(code))."
        }
    }
}

private struct ApifyLimitsResponse: Decodable {
    let data: ApifyLimitsData
}

private struct ApifyLimitsData: Decodable {
    let limits: ApifyLimits
    let current: ApifyCurrentUsage
}

private struct ApifyLimits: Decodable {
    let maxMonthlyUsageUsd: Double?
    let maxActorMemoryGbytes: Double?
}

private struct ApifyCurrentUsage: Decodable {
    let monthlyUsageUsd: Double?
    let monthlyActorComputeUnits: Double?
    let monthlyExternalDataTransferGbytes: Double?
    let actorMemoryGbytes: Double?
}

@MainActor
final class ApifyUsageAPI {

    static let shared = ApifyUsageAPI()

    private init() {}

    func getUsage() async throws -> ApifyUsageInfo {

        let token =
    ApifySettings.shared.apiToken
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )

guard !token.isEmpty else {
    throw ApifyUsageError.missingToken
}

        var components = URLComponents(
            string: "https://api.apify.com/v2/users/me/limits"
        )!

        components.queryItems = [
            URLQueryItem(
                name: "token",
                value: token
            )
        ]

        guard let url = components.url else {
            throw ApifyUsageError.invalidResponse
        }

        let (data, response) =
            try await URLSession.shared.data(from: url)

        guard let http =
            response as? HTTPURLResponse
        else {
            throw ApifyUsageError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            throw ApifyUsageError.requestFailed(
                http.statusCode
            )
        }

        let decoded =
            try JSONDecoder().decode(
                ApifyLimitsResponse.self,
                from: data
            )

        return ApifyUsageInfo(
            usedUSD:
                decoded.data.current.monthlyUsageUsd ?? 0,

            maxUSD:
                decoded.data.limits.maxMonthlyUsageUsd ?? 0,

            actorComputeUnits:
                decoded.data.current.monthlyActorComputeUnits ?? 0,

            externalTransferGB:
                decoded.data.current.monthlyExternalDataTransferGbytes ?? 0,

            actorMemoryGB:
                decoded.data.current.actorMemoryGbytes ?? 0
        )
    }
}
