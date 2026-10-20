import Foundation

enum AppState {
    case idle
    case recording
    case transcribing
    case streaming  // Realtime chunk transcription
}

enum HistoryPeriod: Int {
    case today
    case week
    case all
}

struct HistoryDashboard {
    let entries: [TranscriptionEntry]
    let audioMinutes: Double
    let typingMinutes: Double
    let savedMinutes: Double
    let wordCount: Int
    let wordsPerMinute: Double
    let appCounts: [(name: String, count: Int)]
}

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    let durationSeconds: Double
    let app: String

    init(text: String, duration: Double, app: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.durationSeconds = duration
        self.app = app
    }
}

@Observable
final class StateManager {
    static let shared = StateManager()

    /// Baseline used to compare dictation with ordinary keyboard typing.
    static let typingWordsPerMinute = 40.0

    var state: AppState = .idle
    var levels: [Float] = Array(repeating: 0, count: 100)
    var transcribedText: String = ""
    var frontmostApp: String = ""
    var recordingStartTime: Date?
    var history: [TranscriptionEntry] = []

    private let historyFile: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Pulse")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        historyFile = appDir.appendingPathComponent("history.json")
        loadHistory()
    }

    /// Push multiple levels at once (batch from audio thread)
    func pushLevels(_ newLevels: [Float]) {
        let count = newLevels.count
        if count >= 100 {
            levels = Array(newLevels.suffix(100))
        } else {
            levels.removeFirst(count)
            levels.append(contentsOf: newLevels)
        }
    }

    func pushLevel(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: 100)
    }

    /// Retention window: entries older than this are pruned on load and save.
    private static let retentionInterval: TimeInterval = 72 * 3600  // 72 hours

    func addEntry(text: String, app: String) {
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let entry = TranscriptionEntry(text: text, duration: duration, app: app)
        history.insert(entry, at: 0)
        pruneOldEntries()
        saveHistory()
    }

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
        let before = history.count
        history.removeAll { $0.date < cutoff }
        let removed = before - history.count
        if removed > 0 {
            print("[StateManager] Pruned \(removed) entries older than 72h")
        }
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFile.path),
              let data = try? Data(contentsOf: historyFile),
              let entries = try? {
                  let decoder = JSONDecoder()
                  decoder.dateDecodingStrategy = .iso8601
                  return try decoder.decode([TranscriptionEntry].self, from: data)
              }()
        else { return }
        history = entries
        pruneOldEntries()
        print("[StateManager] Loaded \(history.count) history entries")
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return }
        try? data.write(to: historyFile)
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

}

// MARK: - History Dashboard

extension StateManager {
    func entries(for period: HistoryPeriod, now: Date = Date(), calendar: Calendar = .current) -> [TranscriptionEntry] {
        switch period {
        case .today:
            return history.filter { calendar.isDateInToday($0.date) }
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else {
                return history
            }
            return history.filter { $0.date >= start }
        case .all:
            return history
        }
    }

    func wordCount(for entry: TranscriptionEntry) -> Int {
        entry.text.split(whereSeparator: \.isWhitespace).count
    }

    func dashboard(for period: HistoryPeriod) -> HistoryDashboard {
        let selectedEntries = entries(for: period)
        let words = selectedEntries.reduce(0) { $0 + wordCount(for: $1) }
        let audioMinutes = selectedEntries.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        let typingMinutes = Double(words) / Self.typingWordsPerMinute
        // Contagem por app. Escrito em passos explicitos de proposito: a versao
        // encadeada (grouping + map + sorted com ternario) estoura o type-checker.
        var tally: [String: Int] = [:]
        for entry in selectedEntries where !entry.app.isEmpty {
            tally[entry.app, default: 0] += 1
        }
        var appCounts: [(name: String, count: Int)] = tally.map { (name: $0.key, count: $0.value) }
        appCounts.sort { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return HistoryDashboard(
            entries: selectedEntries,
            audioMinutes: audioMinutes,
            typingMinutes: typingMinutes,
            savedMinutes: typingMinutes - audioMinutes,
            wordCount: words,
            wordsPerMinute: audioMinutes > 0 ? Double(words) / audioMinutes : 0,
            appCounts: appCounts
        )
    }

    func dailySavingsLastSevenDays(now: Date = Date(), calendar: Calendar = .current) -> [(date: Date, savedMinutes: Double)] {
        (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let dayEntries = history.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let words = dayEntries.reduce(0) { $0 + wordCount(for: $1) }
            let audio = dayEntries.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
            return (calendar.startOfDay(for: date), Double(words) / Self.typingWordsPerMinute - audio)
        }
    }
}
