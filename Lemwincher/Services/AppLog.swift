import Foundation
import Observation

/// Gravité d'un événement du journal.
enum LogLevel: String, Codable, CaseIterable {
    case success, info, warning, error

    var label: String {
        switch self {
        case .success: return "Succès"
        case .info: return "Info"
        case .warning: return "Attention"
        case .error: return "Erreur"
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    /// Repère dans le texte partagé.
    var mark: String {
        switch self {
        case .success: return "✓"
        case .info: return "·"
        case .warning: return "!"
        case .error: return "✗"
        }
    }

    var isProblem: Bool { self == .warning || self == .error }
}

/// Partie de l'app concernée.
enum LogCategory: String, Codable, CaseIterable {
    case app = "Application"
    case location = "Localisation"
    case stores = "Magasins"
    case prices = "Prix"
    case products = "Produits"
    case compare = "Comparer"
    case sites = "Sites des enseignes"
    case tracked = "Rayons suivis"
    case list = "Ma liste"
    case budget = "Budget"
    case recalls = "Rappels"
    case fuel = "Carburants"
    case network = "Réseau"
    case backup = "Sauvegarde"
    case recipes = "Recettes"
    case account = "Compte Open Prices"
}

/// Un événement : « Site Aldi : 26 prix enregistrés », « prices.openfoodfacts.org : erreur 502 »…
struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var level: LogLevel
    var category: LogCategory
    var message: String
    var details: String? = nil
    /// Le même événement répété dans la minute (« ×3 ») au lieu de remplir le journal.
    var count: Int = 1
}

/// Journal de l'app (Réglages › Journal) : réussites, alertes et erreurs, à partager pour montrer un problème.
/// Gardé sur l'iPhone (les 500 derniers événements). À n'utiliser que sur le fil principal (voir `Log`).
@Observable
final class AppLog {
    static let shared = AppLog()
    static let maxEntries = 500

    /// Du plus récent au plus ancien.
    private(set) var entries: [LogEntry] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var saveScheduled = false

    /// `fileURL` nil : journal en mémoire seulement (tests).
    init(fileURL: URL? = AppLog.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Lossy<LogEntry>].self, from: data) {
            entries = Array(saved.compactMap(\.value).prefix(AppLog.maxEntries))
        }
    }

    /// Documents/journal.json, sauf pendant les tests d'interface (journal en mémoire).
    static var defaultFileURL: URL? {
        guard !ProcessInfo.processInfo.arguments.contains("-uitest") else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("journal.json")
    }

    func add(_ level: LogLevel, _ category: LogCategory, _ message: String, details: String? = nil,
             date: Date = Date()) {
        if let first = entries.first, first.level == level, first.category == category, first.message == message,
           date.timeIntervalSince(first.date) < 60 {
            entries[0].count += 1
            entries[0].date = date
            if let details { entries[0].details = details }
        } else {
            entries.insert(LogEntry(date: date, level: level, category: category, message: message, details: details), at: 0)
            if entries.count > AppLog.maxEntries {
                entries.removeLast(entries.count - AppLog.maxEntries)
            }
        }
        scheduleSave()
    }

    func clear() {
        entries = []
        scheduleSave()
    }

    /// Alertes et erreurs des dernières 24 h (pastille dans les Réglages).
    func recentProblems(now: Date = Date()) -> Int {
        entries.filter { $0.level.isProblem && now.timeIntervalSince($0.date) < 24 * 3600 }.count
    }

    /// Texte à partager : en-tête (version, iOS, modèle) puis les événements, du plus récent au plus ancien.
    func exportText(appVersion: String, system: String, device: String, now: Date = Date(),
                    entries list: [LogEntry]? = nil) -> String {
        let shown = list ?? entries
        let errors = shown.filter { $0.level == .error }.count
        let warnings = shown.filter { $0.level == .warning }.count
        let stamp = now.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "fr_FR")))
        var lines = [
            "Journal Lemwincher \(appVersion) · iOS \(system) · \(device)",
            "Généré le \(stamp) · \(shown.count) événement\(shown.count > 1 ? "s" : "") (\(errors) erreur\(errors > 1 ? "s" : ""), \(warnings) alerte\(warnings > 1 ? "s" : ""))",
            "",
        ]
        let format = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits).second(.twoDigits).locale(Locale(identifier: "fr_FR"))
        for entry in shown {
            var line = "\(entry.date.formatted(format))  \(entry.level.mark) [\(entry.category.rawValue)] \(entry.message)"
            if entry.count > 1 { line += " (×\(entry.count))" }
            lines.append(line)
            if let details = entry.details?.trimmed, !details.isEmpty {
                lines.append(contentsOf: details.split(separator: "\n").map { "      " + String($0) })
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Enregistre au plus une fois toutes les 2 secondes, sans bloquer l'affichage.
    private func scheduleSave() {
        guard let fileURL, !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            guard let data = try? JSONEncoder().encode(self.entries) else { return }
            DispatchQueue.global(qos: .utility).async {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Modèle de l'iPhone (« iPhone15,4 » pour un iPhone 15), pour le texte partagé.
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated + " (simulateur)"
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone" : machine
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
    }

    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Raccourcis pour écrire dans le journal depuis n'importe où (le journal est mis à jour sur le fil principal).
enum Log {
    static func record(_ level: LogLevel, _ category: LogCategory, _ message: String, details: String? = nil) {
        let date = Date()
        if Thread.isMainThread {
            AppLog.shared.add(level, category, message, details: details, date: date)
        } else {
            DispatchQueue.main.async {
                AppLog.shared.add(level, category, message, details: details, date: date)
            }
        }
    }

    static func success(_ category: LogCategory, _ message: String, details: String? = nil) {
        record(.success, category, message, details: details)
    }

    static func info(_ category: LogCategory, _ message: String, details: String? = nil) {
        record(.info, category, message, details: details)
    }

    static func warning(_ category: LogCategory, _ message: String, details: String? = nil) {
        record(.warning, category, message, details: details)
    }

    static func error(_ category: LogCategory, _ message: String, details: String? = nil) {
        record(.error, category, message, details: details)
    }

    /// « prices.openfoodfacts.org/api/v1/prices » : sans les paramètres (positions, recherches).
    static func describe(_ url: URL?) -> String {
        guard let url else { return "adresse inconnue" }
        return (url.host ?? "") + url.path
    }
}
