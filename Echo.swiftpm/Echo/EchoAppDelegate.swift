import UIKit


final class EchoAppDelegate:
    NSObject,
    UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler:
            @escaping
            () -> Void
    ) {

        FetchDownloadEngine.shared
            .handleBackgroundEvents(
                identifier:
                    identifier,
                completionHandler:
                    completionHandler
            )
    }
}
