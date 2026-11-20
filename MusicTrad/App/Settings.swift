import Foundation

enum TranslationEngine: String, CaseIterable, Identifiable {
    case apple, deepl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: "Apple (sur le Mac, gratuit)"
        case .deepl: "DeepL (clé API gratuite)"
        }
    }
}

/// Clés @AppStorage partagées.
enum SettingsKey {
    static let engine = "translationEngine"
    static let fontSize = "lyricsFontSize"
    static let translationScale = "translationScale"
    static let showOriginal = "showOriginal"
    static let blurInactive = "blurInactiveLines"
    static let syncOffset = "syncOffset"
    static let prefetchNext = "prefetchNext"
    static let floatingWindowEnabled = "floatingWindowEnabled"
    static let openWindowAtLaunch = "openWindowAtLaunch"
    static let cacheLimitMB = "cacheLimitMB"
    static let cacheMaxAgeDays = "cacheMaxAgeDays"
    static let ecoMode = "ecoMode"
    static let ecoAtLaunch = "ecoAtLaunch"
}

enum SettingsDefault {
    static let fontSize: Double = 24
    static let translationScale: Double = 0.85
    static let syncOffset: Double = 0.2
}

/// Lecture des réglages hors des vues (valeurs par défaut si jamais modifiés).
enum Preferences {
    private static var d: UserDefaults { .standard }

    static var syncOffset: Double { d.object(forKey: SettingsKey.syncOffset) as? Double ?? SettingsDefault.syncOffset }
    static var prefetchNext: Bool { d.object(forKey: SettingsKey.prefetchNext) as? Bool ?? true }
    /// Fenêtre flottante désactivée par défaut : à cocher dans Réglages › Général.
    static var floatingWindowEnabled: Bool { d.bool(forKey: SettingsKey.floatingWindowEnabled) }
    /// Démarrer en mode éco (activé par défaut).
    static var ecoAtLaunch: Bool { d.object(forKey: SettingsKey.ecoAtLaunch) as? Bool ?? true }
    static var openWindowAtLaunch: Bool { floatingWindowEnabled && d.bool(forKey: SettingsKey.openWindowAtLaunch) }
    static var cacheLimitMB: Int {
        let v = d.integer(forKey: SettingsKey.cacheLimitMB)
        return v > 0 ? v : CacheManager.defaultLimitMB
    }
    static var cacheMaxAgeDays: Int {
        d.object(forKey: SettingsKey.cacheMaxAgeDays) as? Int ?? CacheManager.defaultMaxAgeDays
    }
}
