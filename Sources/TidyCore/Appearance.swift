import Foundation

/// The two looks of the app: off-white paper or dark.
public enum Appearance: String, Codable, Sendable {
    case light, dark

    public var toggled: Appearance { self == .light ? .dark : .light }
}

/// Remembers the chosen look between launches. Starts as light (off-white) the first time.
public struct AppearanceStore {
    private let defaults: UserDefaults
    private let key = "tidyup.appearance"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Appearance {
        defaults.string(forKey: key).flatMap(Appearance.init(rawValue:)) ?? .light
    }

    public func save(_ appearance: Appearance) {
        defaults.set(appearance.rawValue, forKey: key)
    }
}
