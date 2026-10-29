import SwiftUI
import UniformTypeIdentifiers

@main
struct LulexiaApp: App {
    @StateObject private var reader = ReaderModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: reader)
                .onOpenURL { reader.importPDF($0) }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: ReaderModel
    @State private var importing = false
    @State private var settings = false
    @State private var showingChapters = false
    @State private var showingRhythm = false
    @State private var editingDocumentName = false
    @State private var documentNameDraft = ""
    @State private var documentToHide: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.document == nil { library } else { reader }
        }
        .tint(.teal)
        .overlay(alignment: .topTrailing) { LulapointsToast(store: model.progress) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): model.importPDF(url)
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .alert("Lulexia", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Aceptar") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.save(); model.pause() }
        }
    }

    private var library: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image("LulexiaBrand")
                                .resizable().scaledToFit().frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .accessibilityHidden(true)
                            Text("Lulexia").font(.title.bold())
                            Spacer(minLength: 12)
                            LulapointsButton(store: model.progress, compact: false)
                                .buttonStyle(.borderless)
                        }
                        Text("Leé a tu ritmo").font(.largeTitle.bold())
                        Text("Abrí un PDF, tocá una oración y escuchá. Tus documentos se guardan en este iPad.").foregroundStyle(.secondary)
                        Button { importing = true } label: {
                            Text("Abrir PDF")
                                .frame(minWidth: 140, minHeight: 44, alignment: .center)
                        }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }.padding(.vertical)
                }
                Section("Tus documentos") {
                    if model.files.isEmpty { Text("Todavía no hay documentos.").foregroundStyle(.secondary) }
                    ForEach(model.files, id: \.self) { url in
                        HStack(spacing: 12) {
                            Button { model.open(url) } label: {
                                Label(model.title(for: url), systemImage: "doc.text")
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.borderless)
                            Button("Quitar") { documentToHide = url }
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Quitar \(model.title(for: url)) de la lista")
                        }
                    }
                }
                Section {
                    Button("Probar con un PDF de ejemplo", systemImage: "sparkles") { model.createSample() }
                }
            }
            .alert("¿Quitar de Tus documentos?", isPresented: Binding(
                get: { documentToHide != nil },
                set: { if !$0 { documentToHide = nil } }
            ), presenting: documentToHide) { url in
                Button("Cancelar", role: .cancel) { documentToHide = nil }
                Button("Quitar") { model.hideDocument(url); documentToHide = nil }
            } message: { url in
                Text("¿Seguro que querés quitar «\(model.title(for: url))» de la lista? El PDF seguirá guardado en este iPad; no se borrará.")
            }
        }
    }

    private var reader: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                tool("Biblioteca", "books.vertical") { model.close() }
                Divider()
                tool("Índice de capítulos", "list.bullet.indent") { showingChapters.toggle() }
                    .popover(isPresented: $showingChapters) { chapterList.frame(minWidth: 340, minHeight: 440) }
                tool("Opciones de lectura", "slider.horizontal.3") { settings.toggle() }
                    .popover(isPresented: $settings) { preferences.frame(minWidth: 320, minHeight: 460) }
                tool("Ampliar palabra", "textformat.size", active: model.magnify) { model.magnify.toggle() }
                tool("Resaltar oración", "highlighter", active: model.highlight) { model.highlight.toggle() }
                tool("Voz", "speaker.wave.2", active: model.voiceEnabled) { model.voiceEnabled.toggle() }
                Spacer()
                LulapointsButton(store: model.progress)
            }
            .padding(12).frame(width: 76).background(.thinMaterial)
            .zIndex(1)
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack { documentTitle; Spacer(minLength: 8); pageIndicator; zoomControls }
                    VStack(alignment: .leading, spacing: 4) {
                        documentTitle
                        HStack { pageIndicator; Spacer(minLength: 8); zoomControls }
                    }
                }.padding(.horizontal).padding(.vertical, 8)
                    .clipped()
                if model.magnify && model.wordBandAtTop { wordBand }
                ZStack {
                    PDFReader(model: model)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                    if model.loading { ProgressView("Preparando lectura…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
                }
                if model.magnify && !model.wordBandAtTop { wordBand }
                playback
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
        }
    }
    private var wordBand: some View {
        Text(model.word.isEmpty && !model.hasStartedReading ? "La palabra activa aparecerá aquí" : model.word)
            .font(.system(size: 22 * model.scale, weight: .medium))
            .lineLimit(2).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color.teal.opacity(0.08))
            .accessibilityLabel(model.word.isEmpty ? "Banda de palabra activa" : model.word)
    }
    private var documentTitle: some View {
        HStack(spacing: 8) {
            Image("LulexiaBrand")
                .resizable().scaledToFit().frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            Text(model.currentURL.map { model.title(for: $0) } ?? "PDF")
                .font(.headline).lineLimit(1)
            Button {
                documentNameDraft = model.currentURL.map { model.title(for: $0) } ?? ""
                editingDocumentName = true
            } label: {
                Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Editar nombre del libro")
        }
        .alert("Nombre del libro", isPresented: $editingDocumentName) {
            TextField("Nombre", text: $documentNameDraft)
            Button("Cancelar", role: .cancel) { }
            Button("Guardar") { model.renameCurrentDocument(documentNameDraft) }
                .disabled(documentNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Este nombre se mostrará en el lector y en tu biblioteca.")
        }
    }
    @ViewBuilder private var pageIndicator: some View {
        if let sentence = model.sentence, let pdf = model.document {
            Text("Página \(sentence.page + 1) / \(pdf.pageCount)")
                .font(.callout).foregroundStyle(.secondary).fixedSize()
        }
    }
    private var zoomControls: some View {
        HStack(spacing: 4) {
            tool("Alejar documento", "minus.magnifyingglass") { model.zoom(.farther) }
            tool("Acercar documento", "plus.magnifyingglass") { model.zoom(.closer) }
            Button { model.zoom(.fitWidth) } label: {
                Label("Al ancho", systemImage: "arrow.left.and.right")
                    .font(.callout).fixedSize().padding(.horizontal, 8).frame(minHeight: 44)
            }
            .accessibilityLabel("Ajustar documento al ancho")
        }
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
    private var chapterList: some View {
        NavigationStack {
            List {
                if model.loading {
                    ProgressView("Preparando índice…")
                } else if model.chapters.isEmpty {
                    Text("Este PDF no tiene un índice interno ni encabezados de capítulo reconocibles.")
                        .foregroundStyle(.secondary)
                } else {
                    if model.inferredChapters {
                        Text("Capítulos detectados en el texto. Pueden incluir referencias del índice impreso.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(model.chapters) { chapter in
                        Button {
                            model.goToChapter(chapter)
                            showingChapters = false
                        } label: {
                            HStack(alignment: .top) {
                                Text(chapter.title).multilineTextAlignment(.leading)
                                Spacer()
                                Text("Pág. \(chapter.page + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.leading, CGFloat(min(chapter.level, 4)) * 12)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Índice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showingChapters = false } } }
        }
    }
    private func tool(_ title: String, _ icon: String, active: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2).frame(minWidth: 44, minHeight: 44)
                .background(active == true ? Color.teal.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(title)
        .accessibilityValue(active.map { $0 ? "Activado" : "Desactivado" } ?? "")
    }
    private var playback: some View {
        VStack(spacing: 8) {
        if !model.voiceEnabled {
            Button(model.manualReading ? "Pausar lectura sin voz" : "Iniciar lectura sin voz",
                   systemImage: model.manualReading ? "pause.circle" : "timer") { model.toggleManualReading() }
                .frame(minHeight: 44)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { transport; Divider().frame(height: 32); speed; voiceMenu }
            VStack(spacing: 8) { transport; speed; voiceMenu }
        }
        }
        .padding().frame(maxWidth: .infinity).background(.bar)
        .disabled(model.sentence == nil || model.loading)
    }
    private var transport: some View {
        HStack(spacing: 20) {
            tool("Oración anterior", "backward.end") { model.step(-1) }.disabled(model.index == 0)
            tool(model.playing ? "Pausar" : "Reproducir", model.playing ? "pause.fill" : "play.fill") { model.toggle() }
                .disabled(!model.voiceEnabled)
            tool("Oración siguiente", "forward.end") { model.step(1) }.disabled(model.index + 1 >= model.sentences.count)
            tool("Repetir oración", "arrow.counterclockwise") { model.select(model.index) }
        }
    }
    private var speed: some View {
        Button { showingRhythm = true } label: {
            Label("Ritmo: \(model.stepByStep ? "paso a paso" : model.rateLabel.lowercased())", systemImage: "metronome")
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityHint("Ajustar velocidad de voz y pausas entre oraciones")
        .popover(isPresented: $showingRhythm) {
            NavigationStack {
                Form {
                    rhythmControls
                    Section {
                        Text("Los cambios se aplican desde la siguiente oración, sin interrumpir la actual.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Ritmo de lectura")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showingRhythm = false } } }
            }.frame(minWidth: 340, minHeight: 380)
        }
    }
    @ViewBuilder private var rhythmControls: some View {
        Section {
            Button { model.stepByStep.toggle() } label: {
                HStack {
                    Label("Paso a paso", systemImage: "tortoise")
                    Spacer()
                    if model.stepByStep { Image(systemName: "checkmark.circle.fill") }
                }.frame(minHeight: 44)
            }
            .accessibilityValue(model.stepByStep ? "Activado" : "Desactivado")
            Text("Mucho más lento: una palabra a la vez, con una pausa entre palabras. Tocá otra vez para desactivar.")
                .font(.footnote).foregroundStyle(.secondary)
            Picker("Pausa entre palabras", selection: $model.wordPause) {
                Text("Muy corta · 0,15 s").tag(0.15)
                Text("Corta · 0,325 s (mitad)").tag(0.325)
                Text("Media · 0,50 s").tag(0.5)
                Text("Original · 0,65 s").tag(0.65)
                Text("Larga · 1 s").tag(1.0)
            }
            .pickerStyle(.menu)
            .disabled(!model.stepByStep)
            Text("Se usa en Paso a paso y cambia desde la siguiente oración.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Velocidad de voz") {
            Picker("Velocidad", selection: $model.rate) {
                Text("Muy lenta").tag(0.0)
                Text("Lenta").tag(0.25)
                Text("Media").tag(0.4)
                Text("Normal").tag(0.5)
                if ![0.0, 0.25, 0.4, 0.5].contains(model.rate) {
                    Text(model.rateLabel).tag(model.rate)
                }
            }.pickerStyle(.inline)
                .disabled(model.stepByStep)
        }
        Section("Pausa entre oraciones") {
            Picker("Pausa", selection: $model.sentencePause) {
                Text("Corta").tag(0.4)
                Text("Media").tag(0.85)
                Text("Larga").tag(1.5)
            }.pickerStyle(.segmented)
            Text("Tiempo extra para procesar lo escuchado. Los títulos conservan una pausa mayor.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var voiceMenu: some View {
        Menu {
            Picker("Voz de lectura", selection: $model.voiceID) {
                Text("Español latino automático").tag("")
                ForEach(model.voices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                }
            }
            if model.voices.isEmpty {
                Text("No hay voces en español disponibles")
            }
        } label: {
            Label {
                Text(model.voices.first(where: { $0.identifier == model.voiceID })?.name ?? "Español latino")
                    .lineLimit(1)
            } icon: { Image(systemName: "person.wave.2") }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Seleccionar voz")
        .accessibilityValue(model.voices.first(where: { $0.identifier == model.voiceID }).map { "\($0.name), \($0.language)" } ?? "Español latino automático")
    }
    private var preferences: some View {
        Form {
            Section("Ayudas visuales") {
                Toggle("Resaltar oración", isOn: $model.highlight)
                Toggle("Ampliar palabra en banda fija", isOn: $model.magnify)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Posición de la palabra activa")
                    Picker("Posición de la palabra activa", selection: $model.wordBandAtTop) {
                        Text("Arriba").tag(true)
                        Text("Abajo").tag(false)
                    }.pickerStyle(.segmented)
                }
                Picker("Tamaño de palabra", selection: $model.scale) {
                    Text("1,25×").tag(1.25); Text("1,5×").tag(1.5); Text("2×").tag(2.0); Text("3×").tag(3.0)
                }
            }
            Section("Lectura en voz alta") {
                Toggle("Voz", isOn: $model.voiceEnabled)
                Picker("Voz del sistema", selection: $model.voiceID) {
                    Text("Español latino automático").tag("")
                    ForEach(model.voices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                    }
                }
            }
            rhythmControls
            Section("Ajuste fino de velocidad") {
                Text("Velocidad: \(model.rateLabel.lowercased())")
                Slider(value: $model.rate, in: 0.0...0.6, step: 0.025) { Text("Velocidad de lectura") }
                    .accessibilityValue(model.rateLabel)
                Text("Más lenta a la izquierda; más rápida a la derecha.").font(.footnote).foregroundStyle(.secondary)
                Button("Restablecer velocidad normal") { model.rate = 0.5 }
                Text("La velocidad y las pausas se aplican desde la siguiente oración. Cambiar la voz reinicia la oración actual.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Button("Cerrar opciones") { settings = false } }
        }
    }
}
