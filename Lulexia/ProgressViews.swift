import SwiftUI

struct LulapointsToast: View {
    @ObservedObject var store: ProgressStore
    var body: some View {
        Group {
            if let notice = store.pointsNotice {
                Label("¡Ganaste \(notice.points) Lulapoints!", systemImage: "sparkles")
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.teal.opacity(0.3), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.pointsNotice?.id)
        .allowsHitTesting(false)
    }
}

struct LulapointsButton: View {
    @ObservedObject var store: ProgressStore
    var compact = true
    @State private var showingProgress = false
    var body: some View {
        Button { showingProgress = true } label: {
            if compact {
                VStack(spacing: 3) {
                    Image(systemName: "sparkles")
                    Text(store.ledger.balance.formatted()).font(.caption.bold()).minimumScaleFactor(0.5).lineLimit(1)
                    Text("LP").font(.caption2)
                    if store.storageError != nil { Image(systemName: "exclamationmark.triangle").font(.caption2) }
                }.frame(width: 52).frame(minHeight: 64)
            } else {
                Label("\(store.ledger.balance) Lulapoints", systemImage: "sparkles")
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(minHeight: 44)
            }
        }
        .accessibilityLabel("\(store.ledger.balance) Lulapoints, ver progreso")
        .sheet(isPresented: $showingProgress) { LulapointsPanel(store: store) }
    }
}

struct LulapointsPanel: View {
    @ObservedObject var store: ProgressStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let ledger = store.ledger
                let today = ledger.days.first { $0.id == ledger.dayKey(timeline.date) }
                let streak = ledger.currentStreak(at: timeline.date)
                let next = ledger.nextMilestone(at: timeline.date)
                List {
                    Section {
                        Label("\(ledger.balance) Lulapoints", systemImage: "sparkles").font(.title2.bold())
                        Text("\(streak) días consecutivos").font(.headline)
                        Text("Mejor racha: \(ledger.bestStreak) días")
                        ProgressView(value: min(today?.activeSeconds ?? 0, 120), total: 120)
                        Text(today?.completed == true ? "Hoy cumpliste. ¡Tu racha sigue!" : "Hoy: \(duration(today?.activeSeconds ?? 0)) de 2 min. Sumá lectura para continuar tu racha.")
                        Text("Próximo premio: \(next) días seguidos · +\(LulapointsLedger.milestonePoints(next) ?? 0) LP")
                    }
                    Section("Últimos 14 días") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                            ForEach((-13...0).map { $0 }, id: \.self) { offset in
                                let date = ledger.calendar.date(byAdding: .day, value: offset, to: timeline.date) ?? timeline.date
                                let key = ledger.dayKey(date)
                                let completed = ledger.days.first(where: { $0.id == key })?.completed == true
                                VStack(spacing: 5) {
                                    Text(String(ledger.calendar.component(.day, from: date))).font(.caption)
                                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(completed ? Color.teal : Color.secondary)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(key): \(completed ? "cumplido" : "sin completar")")
                            }
                        }.padding(.vertical, 8)
                        Text("Cada día cuenta con 2 minutos acumulados. La racha exige días consecutivos; hoy tenés hasta medianoche para cumplir.").font(.footnote)
                    }
                    Section("Premios por racha") {
                        Text("3 días: +30 LP · 5 días: +50 LP · 7 días: +100 LP. Después, +100 LP cada 7 días consecutivos.")
                        Text("Una nueva racha puede volver a ganar los hitos. Los puntos ganados se conservan.").font(.footnote).foregroundStyle(.secondary)
                        if ledger.rewards.isEmpty { Text("Tus premios aparecerán acá.").foregroundStyle(.secondary) }
                        ForEach(ledger.rewards.reversed()) { reward in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(reward.milestone) días consecutivos")
                                    Text(reward.earnedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(reward.points) LP").bold()
                            }
                        }
                    }
                    Section("Lectura por libro") {
                        if ledger.sessions.isEmpty { Text("Empezá a leer para registrar tu actividad.").foregroundStyle(.secondary) }
                        ForEach(ledger.documents.filter { document in ledger.sessions.contains { $0.documentID == document.id } }) { document in
                            let sessions = ledger.sessions.filter { $0.documentID == document.id }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title)
                                Text("\(duration(sessions.reduce(0) { $0 + $1.activeSeconds })) · \(sessions.count) sesiones")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Sesiones recientes") {
                        ForEach(Array(ledger.sessions.suffix(20).reversed())) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ledger.documents.first(where: { $0.id == session.documentID })?.title ?? "Documento")
                                Text("\(duration(session.activeSeconds)) · \(session.mode == "manual" ? "Sin voz" : "Con voz")")
                                Text(session.startedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Text("Sin login: el progreso se comparte en este iPad. Se guarda localmente; desinstalar la app puede eliminarlo.")
                        Text("Los días se calculan en la zona horaria del perfil: \(ledger.profile.timeZoneID).")
                        Text("Con voz se cuenta la reproducción, sin las esperas entre fragmentos. Sin voz, usá Iniciar lectura. Todas las velocidades otorgan los mismos premios.")
                    }.font(.footnote).foregroundStyle(.secondary)
                    if let error = store.storageError {
                        Section("Guardado del progreso") {
                            Text(error)
                            Button("Reintentar guardado") { store.retrySaving() }
                        }
                    }
                }
            }
            .navigationTitle("Tu progreso")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .overlay(alignment: .topTrailing) { LulapointsToast(store: store) }
    }
    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return "\(total / 60) min \(total % 60) s"
    }
}
