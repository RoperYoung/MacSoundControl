import Sparkle

final class SparkleUpdaterController {
    private lazy var standardController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func start() {
        _ = standardController
    }

    func checkForUpdates() {
        start()
        standardController.checkForUpdates(nil)
    }
}
