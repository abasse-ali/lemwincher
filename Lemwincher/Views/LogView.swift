import SwiftUI
import UIKit

extension LogLevel {
    var color: Color {
        switch self {
        case .success: return Color.brand
        case .info: return Color.blue
        case .warning: return Color.orange
        case .error: return Color.red
        }
    }
}

/// Réglages › Journal : ce qui s'est passé dans l'app (réussites, alertes, erreurs), à partager pour montrer un problème.
struct LogView: View {
    private let log = AppLog.shared

    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var confirmClear = false
    @State private var copied = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tout"
        case problems = "Problèmes"
        case successes = "Succès"

        var id: String { rawValue }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [LogEntry]
        var id: Date { day }
    }

    private var filtered: [LogEntry] {
        let text = search.trimmed
        return log.entries.filter { entry in
            switch filter {
            case .all: break
            case .problems: if !entry.level.isProblem { return false }
            case .successes: if entry.level != .success { return false }
            }
            guard !text.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(text)
                || entry.category.rawValue.localizedCaseInsensitiveContains(text)
                || (entry.details ?? "").localizedCaseInsensitiveContains(text)
        }
    }

    private func groups(_ entries: [LogEntry]) -> [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { DayGroup(day: $0, entries: byDay[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
    }

    private func exportText(_ entries: [LogEntry]? = nil) -> String {
        log.exportText(appVersion: AppLog.appVersion, system: AppLog.systemVersion, device: AppLog.deviceModel,
                       entries: entries)
    }

    var body: some View {
        let entries = filtered
        List {
            Section {
                Picker("Afficher", selection: $filter) {
                    ForEach(Filter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("logFilter")
            } footer: {
                Text(summary)
            }

            if entries.isEmpty {
                ContentUnavailableView(filter == .problems ? "Aucun problème" : "Journal vide",
                                       systemImage: filter == .problems ? "checkmark.seal" : "list.bullet.rectangle",
                                       description: Text(filter == .problems
                                                         ? "Aucune alerte ni erreur enregistrée."
                                                         : "Les événements de l'app s'afficheront ici."))
            }

            ForEach(groups(entries)) { group in
                Section(dayTitle(group.day)) {
                    ForEach(group.entries) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Chercher dans le journal")
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: exportText(filter == .all && search.trimmed.isEmpty ? nil : entries),
                          subject: Text("Journal Lemwincher")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel("Partager le journal")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = exportText(filter == .all && search.trimmed.isEmpty ? nil : entries)
                        copied = true
                    } label: {
                        Label("Copier le journal", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Effacer le journal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Effacer tout le journal ?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { log.clear() }
        }
        .alert("Journal copié", isPresented: $copied) {
            Button("OK") {}
        } message: {
            Text("Collez-le dans un message pour montrer ce qui s'est passé.")
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private var summary: String {
        let all = log.entries
        let errors = all.filter { $0.level == .error }.count
        let warnings = all.filter { $0.level == .warning }.count
        let successes = all.filter { $0.level == .success }.count
        return "\(all.count) événement\(all.count > 1 ? "s" : "") gardé\(all.count > 1 ? "s" : "") sur l'iPhone (les \(AppLog.maxEntries) derniers) : \(successes) succès, \(warnings) alerte\(warnings > 1 ? "s" : ""), \(errors) erreur\(errors > 1 ? "s" : ""). Touchez un événement pour ses détails ; partagez le journal (↑) pour montrer un problème. Ni votre position ni vos recherches n'y figurent."
    }
}

/// Un événement : icône de gravité, message, partie de l'app et heure ; les détails se déplient.
struct LogRow: View {
    let entry: LogEntry
    @State private var showDetails = false

    var body: some View {
        Button {
            guard entry.details != nil else { return }
            withAnimation(.snappy) { showDetails.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.level.symbol)
                    .font(.body)
                    .foregroundStyle(entry.level.color)
                    .frame(width: 22)
                    .accessibilityLabel(entry.level.label)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.message)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Fmt.join(entry.category.rawValue,
                                  entry.date.formatted(.dateTime.hour().minute().second()),
                                  entry.count > 1 ? "×\(entry.count)" : nil))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showDetails, let details = entry.details {
                        Text(details)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                if entry.details != nil {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
