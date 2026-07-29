import Foundation

enum ApplicationVolumeControlMode: String, CaseIterable {
    case unified
    case separate

    static let defaultsKey = "applicationVolumeControlMode"

    static func resolve(storedRawValue: String?) -> ApplicationVolumeControlMode {
        guard let storedRawValue,
              let mode = ApplicationVolumeControlMode(rawValue: storedRawValue) else {
            return .separate
        }
        return mode
    }

    static func load(from defaults: UserDefaults) -> ApplicationVolumeControlMode {
        resolve(storedRawValue: defaults.string(forKey: defaultsKey))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
