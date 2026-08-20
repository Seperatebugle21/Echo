import Foundation
import Observation

enum ApifyDownloadMethod: String, CaseIterable, Identifiable {
    case youtube
    case spotify

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .youtube:
            return "YouTube"

        case .spotify:
            return "Spotify"
        }
    }
}


@MainActor
@Observable
final class ApifySettings {

    static let shared = ApifySettings()

    private let accountsKey =
        "echo.apify.accounts"

    private let activeAccountKey =
        "echo.apify.activeAccount"

    private let methodKey =
        "echo.apify.downloadMethod"


    var accounts: [ApifyAccount] = []

    var activeAccountID: UUID? {
        didSet {
            if let activeAccountID {

                UserDefaults.standard.set(
                    activeAccountID.uuidString,
                    forKey: activeAccountKey
                )

            } else {

                UserDefaults.standard.removeObject(
                    forKey: activeAccountKey
                )
            }
        }
    }


    var downloadMethod: ApifyDownloadMethod {
        didSet {

            UserDefaults.standard.set(
                downloadMethod.rawValue,
                forKey: methodKey
            )
        }
    }


    var activeAccount: ApifyAccount? {

        guard let activeAccountID else {
            return nil
        }

        return accounts.first {
            $0.id == activeAccountID
        }
    }


    var apiToken: String {

        activeAccount?.token ?? ""
    }


    var isConfigured: Bool {

        !apiToken
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }


    private init() {

        // Method

        if
            let savedMethod =
                UserDefaults.standard.string(
                    forKey: methodKey
                ),
            let method =
                ApifyDownloadMethod(
                    rawValue: savedMethod
                )
        {
            downloadMethod = method
        } else {
            downloadMethod = .youtube
        }


        // Accounts metadata

        if
            let data =
                UserDefaults.standard.data(
                    forKey: accountsKey
                ),
            let savedAccounts =
                try? JSONDecoder().decode(
                    [ApifyStoredAccount].self,
                    from: data
                )
        {

            accounts =
                savedAccounts.compactMap {
                    stored in

                    guard
                        let token =
                            KeychainHelper.read(
                                tokenKey(
                                    for: stored.id
                                )
                            )
                    else {
                        return nil
                    }

                    return ApifyAccount(
                        id: stored.id,
                        name: stored.name,
                        token: token
                    )
                }
        }


        // Active

        if
            let string =
                UserDefaults.standard.string(
                    forKey: activeAccountKey
                ),
            let id =
                UUID(uuidString: string),
            accounts.contains(
                where: { $0.id == id }
            )
        {
            activeAccountID = id

        } else {

            activeAccountID =
                accounts.first?.id
        }
    }


    // MARK: - Add

    func addAccount(
        name: String,
        token: String
    ) {

        let cleanToken =
            token.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !cleanToken.isEmpty else {
            return
        }

        let account =
            ApifyAccount(
                name:
                    name.isEmpty
                    ? "Apify Account"
                    : name,

                token: cleanToken
            )

        accounts.append(account)

        KeychainHelper.save(
            cleanToken,
            for: tokenKey(
                for: account.id
            )
        )

        saveAccounts()

        if activeAccountID == nil {
            activeAccountID = account.id
        }
    }


    // MARK: - Select

    func setActive(
        _ account: ApifyAccount
    ) {

        activeAccountID =
            account.id
    }


    // MARK: - Remove

    func removeAccount(
        _ account: ApifyAccount
    ) {

        KeychainHelper.delete(
            tokenKey(
                for: account.id
            )
        )

        accounts.removeAll {
            $0.id == account.id
        }

        if
            activeAccountID ==
            account.id
        {

            activeAccountID =
                accounts.first?.id
        }

        saveAccounts()
    }


    // MARK: - Save

    private func saveAccounts() {

        let stored =
            accounts.map {
                ApifyStoredAccount(
                    id: $0.id,
                    name: $0.name
                )
            }

        guard
            let data =
                try? JSONEncoder().encode(
                    stored
                )
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: accountsKey
        )
    }


    private func tokenKey(
        for id: UUID
    ) -> String {

        "echo.apify.account.\(id.uuidString)"
    }
}


private struct ApifyStoredAccount:
    Codable {

    let id: UUID
    let name: String
}
