import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ar, en
    var id: String { rawValue }
    var layoutDirection: LayoutDirection { self == .ar ? .rightToLeft : .leftToRight }
    var locale: Locale { Locale(identifier: self == .ar ? "ar_SA" : "en_SA") }
    var displayName: String { self == .ar ? "العربية" : "English" }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var hasSeenIntro: Bool { didSet { defaults.set(hasSeenIntro, forKey: "hasSeenIntro") } }
    @Published var autoSkipIntro: Bool { didSet { defaults.set(autoSkipIntro, forKey: "autoSkipIntro") } }
    @Published var reduceMotionOverride: Bool { didSet { defaults.set(reduceMotionOverride, forKey: "reduceMotionOverride") } }
    @Published var graphicsQuality: GraphicsQuality { didSet { defaults.set(graphicsQuality.rawValue, forKey: "graphicsQuality") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .ar
        hasSeenIntro = defaults.bool(forKey: "hasSeenIntro")
        autoSkipIntro = defaults.bool(forKey: "autoSkipIntro")
        reduceMotionOverride = defaults.bool(forKey: "reduceMotionOverride")
        graphicsQuality = GraphicsQuality(rawValue: defaults.string(forKey: "graphicsQuality") ?? "") ?? .high
    }

    /// Picks the Arabic or English string for the current language.
    func t(_ ar: String, _ en: String) -> String { language == .ar ? ar : en }

    /// Formats a price in Saudi riyals.
    func price(_ value: Double) -> String {
        let digits = value.rounded() == value ? 0 : 2
        let number = value.formatted(.number.precision(.fractionLength(digits)).locale(language.locale))
        return language == .ar ? "\(number) ر.س" : "SAR \(number)"
    }
}
