import SwiftUI
import SwiftData

struct PointsNotice: Identifiable {
    let id = UUID()
    let points: Int
}

@Model final class LocalProgressSnapshot {
    @Attribute(.unique) var key: String
    var payload: Data
    init(key: String, payload: Data) { self.key = key; self.payload = payload }
}

@MainActor final class ProgressStore: ObservableObject {
    @Published private(set) var ledger = LulapointsLedger()
    @Published private(set) var storageError: String?
    @Published private(set) var isTracking = false
    @Published private(set) var pointsNotice: PointsNotice?
    private var knownRewardIDs: Set<String> = []
    private var noticeQueue: [PointsNotice] = []
    private var noticeTask: Task<Void, Never>?
    private var container: ModelContainer?
    private var snapshot: LocalProgressSnapshot?
    private var timer: Timer?
    private var lastUptime: TimeInterval?
    private var unsavedSeconds: Double = 0
    private var documentID: UUID?
    private var sessionID: UUID?
    private var mode = "voice"
    private var ready = false
    private let configuration: ModelConfiguration

    init(configuration: ModelConfiguration? = nil) {
        self.configuration = configuration ?? ModelConfiguration("LulexiaProgress", cloudKitDatabase: .none)
        openStorage()
    }
    private func openStorage() {
        do {
            let container = try ModelContainer(for: LocalProgressSnapshot.self, configurations: configuration)
            container.mainContext.autosaveEnabled = false
            self.container = container
            let values = try container.mainContext.fetch(FetchDescriptor<LocalProgressSnapshot>())
            if let stored = values.first(where: { $0.key == "local-profile" }) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                ledger = try decoder.decode(LulapointsLedger.self, from: stored.payload)
                guard ledger.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                snapshot = stored
            }
            // Restored rewards are history, not new gains to announce.
            knownRewardIDs = Set(ledger.rewards.map(\.id))
            ready = true
            persist()
        } catch {
            storageError = "No se pudo abrir el progreso local. No se reemplazaron tus datos. \(error.localizedDescription)"
        }
    }
    func retrySaving() {
        if ready { persist() } else { openStorage() }
    }
    func beginDocument(fileKey: String, title: String) {
        finishDocument()
        guard ready else { return }
        documentID = ledger.documentID(fileKey: fileKey, title: title)
        persist()
    }
    func renameDocument(fileKey: String, title: String) {
        guard ready else { return }
        _ = ledger.documentID(fileKey: fileKey, title: title)
        persist()
    }
    func start(mode newMode: String) {
        guard ready, documentID != nil, !isTracking else { return }
        if mode != newMode { sessionID = nil }
        mode = newMode
        isTracking = true
        lastUptime = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkpoint() }
        }
    }
    func pause() {
        if isTracking { checkpoint() }
        isTracking = false
        lastUptime = nil
        timer?.invalidate()
        timer = nil
        persist()
    }
    func finishDocument() {
        pause()
        documentID = nil
        sessionID = nil
    }
    func checkpoint() {
        guard isTracking, let previous = lastUptime, let documentID else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        lastUptime = uptime
        // Never award suspended/background time after a delayed timer callback.
        let elapsed = min(5, max(0, uptime - previous))
        guard elapsed > 0 else { return }
        if sessionID == nil { sessionID = UUID() }
        let now = Date()
        let oldBalance = ledger.balance
        ledger.record(sessionID: sessionID!, documentID: documentID, mode: mode,
            from: now.addingTimeInterval(-elapsed), to: now)
        unsavedSeconds += elapsed
        if unsavedSeconds >= 5 || ledger.balance != oldBalance { persist() }
    }
    func persist() {
        guard ready, let context = container?.mainContext else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let payload = try encoder.encode(ledger)
            if let snapshot { snapshot.payload = payload }
            else {
                let value = LocalProgressSnapshot(key: "local-profile", payload: payload)
                context.insert(value)
                snapshot = value
            }
            try context.save()
            let newRewards = ledger.rewards.filter { !knownRewardIDs.contains($0.id) }
            knownRewardIDs.formUnion(newRewards.map(\.id))
            if !newRewards.isEmpty {
                noticeQueue.append(PointsNotice(points: newRewards.reduce(0) { $0 + $1.points }))
                showNextNotice()
            }
            unsavedSeconds = 0
            storageError = nil
        } catch {
            storageError = "No se pudo guardar el progreso. Volvé a intentar. \(error.localizedDescription)"
        }
    }
    private func showNextNotice() {
        guard pointsNotice == nil, !noticeQueue.isEmpty else { return }
        let notice = noticeQueue.removeFirst()
        pointsNotice = notice
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        noticeTask = Task { [weak self] in
            try? await clock.sleep(until: deadline)
            guard !Task.isCancelled, let self, self.pointsNotice?.id == notice.id else { return }
            self.pointsNotice = nil
            self.noticeTask = nil
            self.showNextNotice()
        }
    }
}
