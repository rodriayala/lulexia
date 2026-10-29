import Foundation

struct LocalReaderProfile: Codable {
    var id = UUID()
    var accountID: String? = nil
    var createdAt = Date()
    var timeZoneID = TimeZone.current.identifier
}
struct ProgressDocument: Codable, Identifiable {
    var id = UUID()
    var fileKey: String
    var title: String
}
struct ReadingSession: Codable, Identifiable {
    var id = UUID()
    var profileID: UUID
    var documentID: UUID
    var startedAt: Date
    var lastActivityAt: Date
    var activeSeconds: Double = 0
    var mode: String
}
struct ReadingDay: Codable, Identifiable {
    var id: String // Gregorian YYYY-MM-DD in the profile's time zone.
    var activeSeconds: Double = 0
    var requiredSeconds: Double = 120
    var completed: Bool { activeSeconds >= requiredSeconds }
}
struct StreakReward: Codable, Identifiable {
    var id: String
    var profileID: UUID
    var streakStart: String
    var milestone: Int
    var points: Int
    var earnedAt: Date
    var ruleVersion = 1
}

/// Portable business rules: no UI, speech, or database dependencies.
struct LulapointsLedger: Codable {
    var schemaVersion = 1
    var profile = LocalReaderProfile()
    var documents: [ProgressDocument] = []
    var sessions: [ReadingSession] = []
    var days: [ReadingDay] = []
    var rewards: [StreakReward] = []
    var balance: Int { rewards.reduce(0) { $0 + $1.points } }
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: profile.timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var formatter: DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = calendar
        value.timeZone = calendar.timeZone
        value.dateFormat = "yyyy-MM-dd"
        return value
    }
    func dayKey(_ date: Date) -> String { formatter.string(from: date) }
    func previousDay(_ key: String) -> String? {
        guard let date = formatter.date(from: key), let previous = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return dayKey(previous)
    }
    func currentStreak(at now: Date) -> Int {
        let completed = Set(days.filter(\.completed).map(\.id))
        var cursor = dayKey(now)
        if !completed.contains(cursor) { cursor = previousDay(cursor) ?? "" }
        var count = 0
        while completed.contains(cursor) {
            count += 1
            cursor = previousDay(cursor) ?? ""
        }
        return count
    }
    var bestStreak: Int {
        var previous: String?
        var count = 0
        var best = 0
        for day in days.filter(\.completed).sorted(by: { $0.id < $1.id }) {
            count = previousDay(day.id) == previous ? count + 1 : 1
            best = max(best, count)
            previous = day.id
        }
        return best
    }
    static func milestonePoints(_ day: Int) -> Int? {
        switch day {
        case 3: return 30
        case 5: return 50
        case 7: return 100
        default: return day > 7 && day.isMultiple(of: 7) ? 100 : nil
        }
    }
    func nextMilestone(at now: Date) -> Int {
        let current = currentStreak(at: now)
        return [3, 5, 7].first(where: { $0 > current }) ?? ((current / 7 + 1) * 7)
    }
    mutating func documentID(fileKey: String, title: String) -> UUID {
        if let index = documents.firstIndex(where: { $0.fileKey == fileKey }) {
            documents[index].title = title
            return documents[index].id
        }
        let value = ProgressDocument(fileKey: fileKey, title: title)
        documents.append(value)
        return value.id
    }
    /// Session and day totals are updated together; callers persist the whole ledger atomically.
    mutating func record(sessionID: UUID, documentID: UUID, mode: String, from start: Date, to end: Date) {
        guard end > start, end.timeIntervalSince(start).isFinite else { return }
        let index: Int
        if let existing = sessions.firstIndex(where: { $0.id == sessionID }) {
            index = existing
        } else {
            sessions.append(ReadingSession(id: sessionID, profileID: profile.id, documentID: documentID,
                startedAt: start, lastActivityAt: start, mode: mode))
            index = sessions.count - 1
        }
        // Ignore overlapping checkpoints, including retries after a save failure.
        var cursor = max(start, sessions[index].lastActivityAt)
        guard end > cursor else { return }
        sessions[index].activeSeconds += end.timeIntervalSince(cursor)
        sessions[index].lastActivityAt = end
        while cursor < end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else { break }
            let boundary = min(end, nextDay)
            let key = dayKey(cursor)
            if let day = days.firstIndex(where: { $0.id == key }) {
                days[day].activeSeconds += boundary.timeIntervalSince(cursor)
            } else {
                days.append(ReadingDay(id: key, activeSeconds: boundary.timeIntervalSince(cursor)))
            }
            cursor = boundary
        }
        awardMilestones(at: end)
    }
    private mutating func awardMilestones(at date: Date) {
        var previous: String?
        var start = ""
        var count = 0
        for day in days.filter(\.completed).sorted(by: { $0.id < $1.id }) {
            if previousDay(day.id) == previous { count += 1 }
            else { count = 1; start = day.id }
            if let points = Self.milestonePoints(count) {
                let key = "\(profile.id.uuidString):\(start):\(count):v1"
                if !rewards.contains(where: { $0.id == key }) {
                    rewards.append(StreakReward(id: key, profileID: profile.id, streakStart: start,
                        milestone: count, points: points, earnedAt: date))
                }
            }
            previous = day.id
        }
    }
}
