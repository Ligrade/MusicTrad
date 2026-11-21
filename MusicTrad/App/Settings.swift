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
    static let frenchToEnglish = "frenchToEnglish"
    static let translationHidden = "translationHidden"
    static let libraryFavorites = "libraryFavorites"
    static let settingsTab = "settingsTab"
    static let floatingWindowEnabled = "floatingWindowEnabled"
    static let openWindowAtLaunch = "openWindowAtLaunch"
    static let cacheLimitMB = "cacheLimitMB"
    static let cacheMaxAgeDays = "cacheMaxAgeDays"
    static let ecoMode = "ecoMode"
    static let ecoAtLaunch = "ecoAtLaunch"
    static let autoEcoMinutes = "autoEcoMinutes"
    static let myStationURL = "myStationURL"
}

enum SettingsDefault {
    static let fontSize: Double = 24
    static let translationScale: Double = 0.85
    static let syncOffset: Double = 0
}

/// Lecture des réglages hors des vues (valeurs par défaut si jamais modifiés).
enum Preferences {
    private static var d: UserDefaults { .standard }

    static var syncOffset: Double { d.object(forKey: SettingsKey.syncOffset) as? Double ?? SettingsDefault.syncOffset }
    /// Traduire les chansons en français en anglais (désactivé par défaut).
    static var frenchToEnglish: Bool { d.bool(forKey: SettingsKey.frenchToEnglish) }
    static var prefetchNext: Bool { d.object(forKey: SettingsKey.prefetchNext) as? Bool ?? false }
    /// Fenêtre flottante désactivée par défaut : à cocher dans Réglages › Général.
    static var floatingWindowEnabled: Bool { d.bool(forKey: SettingsKey.floatingWindowEnabled) }
    /// Démarrer en mode éco (désactivé par défaut).
    static var ecoAtLaunch: Bool { d.object(forKey: SettingsKey.ecoAtLaunch) as? Bool ?? false }
    /// Passage automatique en mode éco après ce nombre de minutes sans regarder l'app (0 = jamais ; 30 min par défaut).
    static var autoEcoMinutes: Int { d.object(forKey: SettingsKey.autoEcoMinutes) as? Int ?? 30 }
    static var openWindowAtLaunch: Bool { floatingWindowEnabled && d.bool(forKey: SettingsKey.openWindowAtLaunch) }
    static var cacheLimitMB: Int {
        let v = d.integer(forKey: SettingsKey.cacheLimitMB)
        return v > 0 ? v : CacheManager.defaultLimitMB
    }
    static var cacheMaxAgeDays: Int {
        let v = d.object(forKey: SettingsKey.cacheMaxAgeDays) as? Int ?? CacheManager.defaultMaxAgeDays
        // Anciens choix (6 mois, 1 an, jamais) : ramenés au maximum, 3 mois.
        guard CacheManager.maxAgeChoices.contains(where: { $0.days == v }) else {
            d.set(CacheManager.defaultMaxAgeDays, forKey: SettingsKey.cacheMaxAgeDays)
            return CacheManager.defaultMaxAgeDays
        }
        return v
    }
}
