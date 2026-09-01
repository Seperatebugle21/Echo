import Foundation

struct ApifyAccountUsage {

    let usedUSD: Double
    let maxUSD: Double

    let computeUnits: Double

    let externalTransferGB: Double
    let maxExternalTransferGB: Double

    let actorMemoryGB: Double
    let maxActorMemoryGB: Double

    var usageFraction: Double {

        guard maxUSD > 0 else {
            return 0
        }

        return min(
            usedUSD / maxUSD,
            1
        )
    }
}


enum ApifyAccountUsageError:
    LocalizedError {

    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {

        switch self {

        case .invalidResponse:
            return "Invalid Apify response."

        case .requestFailed(let code):
            return "Apify returned HTTP \(code)."
        }
    }
}


enum ApifyAccountUsageAPI {

    static func load(
        token: String
    ) async throws -> ApifyAccountUsage {

        let url =
            URL(
                string:
                    "https://api.apify.com/v2/users/me/limits"
            )!

        var request =
            URLRequest(url: url)

        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField:
                "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Accept"
        )

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )

        guard
            let http =
                response as? HTTPURLResponse
        else {
            throw
                ApifyAccountUsageError
                    .invalidResponse
        }

        guard 200..<300 ~= http.statusCode
        else {

            throw
                ApifyAccountUsageError
                    .requestFailed(
                        http.statusCode
                    )
        }

        let decoded =
            try JSONDecoder().decode(
                ApifyLimitsResponse.self,
                from: data
            )

        return ApifyAccountUsage(
            usedUSD:
                decoded.data.current
                    .monthlyUsageUsd,

            maxUSD:
                decoded.data.limits
                    .maxMonthlyUsageUsd,

            computeUnits:
                decoded.data.current
                    .monthlyActorComputeUnits,

            externalTransferGB:
                decoded.data.current
                    .monthlyExternalDataTransferGbytes,

            maxExternalTransferGB:
                decoded.data.limits
                    .maxMonthlyExternalDataTransferGbytes,

            actorMemoryGB:
                decoded.data.current
                    .actorMemoryGbytes,

            maxActorMemoryGB:
                decoded.data.limits
                    .maxActorMemoryGbytes
        )
    }
}


private struct ApifyLimitsResponse:
    Decodable {

    let data: DataObject

    struct DataObject:
        Decodable {

        let limits: Limits
        let current: Current
    }


    struct Limits:
        Decodable {

        let maxMonthlyUsageUsd: Double

        let maxMonthlyExternalDataTransferGbytes:
            Double

        let maxActorMemoryGbytes:
            Double
    }


    struct Current:
        Decodable {

        let monthlyUsageUsd: Double

        let monthlyActorComputeUnits:
            Double

        let monthlyExternalDataTransferGbytes:
            Double

        let actorMemoryGbytes:
            Double
    }
}
