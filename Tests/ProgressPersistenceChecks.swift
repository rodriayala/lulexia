import Foundation
import SwiftData

@main struct ProgressPersistenceChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lulexia-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.store")
        let config = ModelConfiguration("Test", url: url, cloudKitDatabase: .none)
        let store = ProgressStore(configuration: config)
        precondition(store.storageError == nil)
        let profileID = store.ledger.profile.id
        store.beginDocument(fileKey: "book.pdf", title: "Libro")
        store.renameDocument(fileKey: "book.pdf", title: "Otro nombre")
        store.finishDocument()
        let restored = ProgressStore(configuration: config)
        precondition(restored.storageError == nil)
        precondition(restored.ledger.profile.id == profileID)
        precondition(restored.ledger.documents.count == 1 && restored.ledger.documents[0].title == "Otro nombre")
        precondition(restored.ledger.sessions.isEmpty && restored.ledger.balance == 0, "Opening a book must not create activity")
        // Exercise real SwiftData persistence of a completed 3-day streak.
        var ledger = restored.ledger
        ledger.profile.timeZoneID = "UTC"
        let documentID = ledger.documents[0].id
        for day in 1...3 {
            let start = ISO8601DateFormatter().date(from: "2026-10-0\(day)T12:00:00Z")!
            ledger.record(sessionID: UUID(), documentID: documentID, mode: "voice", from: start, to: start.addingTimeInterval(120))
        }
        let container = try ModelContainer(for: LocalProgressSnapshot.self, configurations: config)
        let snapshot = try container.mainContext.fetch(FetchDescriptor<LocalProgressSnapshot>()).first!
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        snapshot.payload = try encoder.encode(ledger)
        try container.mainContext.save()
        let third = ProgressStore(configuration: config)
        precondition(third.storageError == nil && third.ledger.balance == 30)
        precondition(third.ledger.profile.id == profileID && third.ledger.sessions.count == 3)
        // Unsupported future data must remain untouched rather than resetting the profile.
        ledger.schemaVersion = 2
        let futurePayload = try encoder.encode(ledger)
        snapshot.payload = futurePayload
        try container.mainContext.save()
        let unsupported = ProgressStore(configuration: config)
        precondition(unsupported.storageError != nil)
        unsupported.persist()
        let verification = try ModelContainer(for: LocalProgressSnapshot.self, configurations: config)
        let protectedPayload = try verification.mainContext.fetch(FetchDescriptor<LocalProgressSnapshot>()).first!.payload
        precondition(protectedPayload == futurePayload)
        let tracking = ProgressStore(configuration: ModelConfiguration("Tracking", url: directory.appendingPathComponent("tracking.store"), cloudKitDatabase: .none))
        tracking.beginDocument(fileKey: "tracking.pdf", title: "Contador")
        tracking.start(mode: "manual")
        try await Task.sleep(nanoseconds: 50_000_000)
        tracking.pause()
        let recorded = tracking.ledger.sessions.first!.activeSeconds
        precondition(recorded > 0 && recorded < 1)
        tracking.checkpoint()
        precondition(tracking.ledger.sessions.first!.activeSeconds == recorded, "Paused time must not count")
        tracking.finishDocument()
        precondition(!tracking.isTracking)
        var rewardLedger = LulapointsLedger()
        rewardLedger.profile.timeZoneID = "UTC"
        let rewardBook = rewardLedger.documentID(fileKey: "reward.pdf", title: "Premio")
        let now = Date()
        for offset in -2...0 {
            let start = rewardLedger.calendar.date(byAdding: .day, value: offset, to: rewardLedger.calendar.startOfDay(for: now))!
            rewardLedger.record(sessionID: UUID(), documentID: rewardBook, mode: "voice", from: start,
                to: start.addingTimeInterval(offset == 0 ? 119.99 : 120))
        }
        let rewardConfig = ModelConfiguration("Rewards", url: directory.appendingPathComponent("rewards.store"), cloudKitDatabase: .none)
        let rewardContainer = try ModelContainer(for: LocalProgressSnapshot.self, configurations: rewardConfig)
        rewardContainer.mainContext.insert(LocalProgressSnapshot(key: "local-profile", payload: try encoder.encode(rewardLedger)))
        try rewardContainer.mainContext.save()
        let rewardStore = ProgressStore(configuration: rewardConfig)
        precondition(rewardStore.pointsNotice == nil, "Loading history must not show a popup")
        rewardStore.beginDocument(fileKey: "reward.pdf", title: "Premio")
        rewardStore.start(mode: "manual")
        try await Task.sleep(nanoseconds: 50_000_000)
        rewardStore.pause()
        precondition(rewardStore.pointsNotice?.points == 30 && rewardStore.ledger.balance == 30)
        let noticeID = rewardStore.pointsNotice?.id
        rewardStore.persist()
        precondition(rewardStore.pointsNotice?.id == noticeID, "Saving again must not repeat the popup")
        let rewardRestored = ProgressStore(configuration: rewardConfig)
        precondition(rewardRestored.ledger.balance == 30 && rewardRestored.pointsNotice == nil)
        // Allow scheduler latency on a busy machine without extending the UI's deadline.
        let timeout = ContinuousClock().now.advanced(by: .seconds(8))
        while rewardStore.pointsNotice != nil && ContinuousClock().now < timeout {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(rewardStore.pointsNotice == nil, "Popup must close after 5 seconds")
        print("SwiftData: identidad, reapertura, premios, contador/pausa y protección de esquemas futuros correctos")
        print("Popup: importe ganado, sin repetición al guardar/reabrir y cierre automático a los 5 segundos correctos")
    }
}
