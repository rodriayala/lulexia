import Foundation

@main struct GamificationChecks {
    static func main() throws {
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        var ledger = LulapointsLedger()
        ledger.profile.timeZoneID = "America/Argentina/Buenos_Aires"
        let book = ledger.documentID(fileKey: "sample.pdf", title: "Ejemplo")
        func addDay(_ day: Int, to value: inout LulapointsLedger) {
            let start = date(String(format: "2026-10-%02dT15:00:00Z", day))
            value.record(sessionID: UUID(), documentID: book, mode: "voice", from: start, to: start.addingTimeInterval(120))
        }
        addDay(1, to: &ledger)
        let second = date("2026-10-02T15:00:00Z")
        let session = UUID()
        ledger.record(sessionID: session, documentID: book, mode: "manual", from: second, to: second.addingTimeInterval(60))
        precondition(ledger.currentStreak(at: second) == 1, "Incomplete today keeps yesterday's streak")
        ledger.record(sessionID: session, documentID: book, mode: "manual", from: second.addingTimeInterval(60), to: second.addingTimeInterval(120))
        let total = ledger.sessions.first(where: { $0.id == session })!.activeSeconds
        ledger.record(sessionID: session, documentID: book, mode: "manual", from: second, to: second.addingTimeInterval(120))
        precondition(ledger.sessions.first(where: { $0.id == session })!.activeSeconds == total, "Retry must not count twice")
        for day in 3...14 {
            addDay(day, to: &ledger)
            if day == 3 { precondition(ledger.balance == 30) }
            if day == 5 { precondition(ledger.balance == 80) }
            if day == 7 { precondition(ledger.balance == 180) }
        }
        precondition(ledger.balance == 280 && ledger.rewards.count == 4)
        precondition(ledger.currentStreak(at: date("2026-10-15T15:00:00Z")) == 14)
        precondition(ledger.currentStreak(at: date("2026-10-16T15:00:00Z")) == 0)
        precondition(ledger.nextMilestone(at: date("2026-10-14T15:00:00Z")) == 21)
        for day in 16...18 { addDay(day, to: &ledger) }
        precondition(ledger.balance == 310 && ledger.bestStreak == 14)
        precondition(ledger.currentStreak(at: date("2026-10-18T15:00:00Z")) == 3)
        let before = ledger.balance
        addDay(18, to: &ledger)
        precondition(ledger.balance == before, "Same milestone cannot be awarded twice")
        precondition(ledger.documentID(fileKey: "sample.pdf", title: "Renombrado") == book)
        precondition(ledger.documents.count == 1 && ledger.sessions.allSatisfy { $0.profileID == ledger.profile.id })
        var midnight = LulapointsLedger()
        midnight.profile.timeZoneID = "America/Argentina/Buenos_Aires"
        let start = date("2026-10-03T02:59:00Z")
        midnight.record(sessionID: UUID(), documentID: book, mode: "voice", from: start, to: start.addingTimeInterval(180))
        precondition(midnight.days.first(where: { $0.id == "2026-10-02" })?.activeSeconds == 60)
        precondition(midnight.days.first(where: { $0.id == "2026-10-03" })?.activeSeconds == 120)
        precondition(midnight.currentStreak(at: start.addingTimeInterval(180)) == 1)
        var dst = LulapointsLedger()
        dst.profile.timeZoneID = "America/New_York"
        precondition(dst.previousDay("2026-03-09") == "2026-03-08")
        precondition(dst.previousDay("2026-11-02") == "2026-11-01")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(LulapointsLedger.self, from: encoder.encode(ledger))
        precondition(restored.profile.id == ledger.profile.id && restored.balance == ledger.balance)
        precondition(restored.currentStreak(at: date("2026-10-18T15:00:00Z")) == 3)
        precondition(restored.documents.first?.title == "Renombrado")
        print("Gamificación: hitos 3/5/7/14, reinicio, hoy pendiente, idempotencia, medianoche, DST, identidad y serialización correctos")
    }
}
