import SwiftUI
import PDFKit
import AVFoundation
import NaturalLanguage

struct Sentence: Identifiable {
    let id: Int
    let page: Int
    let range: NSRange
    let text: String
    var pauseBefore: Double = 0.85
}

struct ChapterEntry: Identifiable {
    let id = UUID()
    let title: String
    let page: Int
    let level: Int
    let destination: PDFDestination?
    let sourceRange: NSRange?
}

enum DocumentZoomAction { case closer, farther, fitWidth }
struct DocumentZoomRequest {
    let id = UUID()
    let action: DocumentZoomAction
}

struct ChapterJump {
    let id = UUID()
    let destination: PDFDestination
}

@MainActor
final class ReaderModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    let progress = ProgressStore()
    @Published private(set) var manualReading = false
    @Published var files: [URL] = []
    @Published private var documentNames = UserDefaults.standard.dictionary(forKey: "documentNames") as? [String: String] ?? [:]
    func title(for url: URL) -> String {
        documentNames[url.lastPathComponent] ?? url.deletingPathExtension().lastPathComponent
    }
    func renameCurrentDocument(_ proposedName: String) {
        guard let url = currentURL else { return }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        documentNames[url.lastPathComponent] = name
        UserDefaults.standard.set(documentNames, forKey: "documentNames")
        progress.renameDocument(fileKey: url.lastPathComponent, title: name)
    }
    @Published var document: PDFDocument?
    @Published var currentURL: URL?
    @Published var sentences: [Sentence] = []
    @Published var zoomRequest: DocumentZoomRequest?
    @Published var chapters: [ChapterEntry] = []
    @Published var inferredChapters = false
    @Published var chapterJump: ChapterJump?
    @Published var index = 0
    @Published var playing = false
    @Published var paused = false
    @Published var loading = false
    @Published var message: String?
    @Published var word = ""
    @Published private(set) var hasStartedReading = false
    @Published var wordRange: NSRange?
    @Published var stepByStep = UserDefaults.standard.bool(forKey: "stepByStep") {
        didSet { UserDefaults.standard.set(stepByStep, forKey: "stepByStep") }
    }
    @Published var wordPause: Double = UserDefaults.standard.object(forKey: "wordPause") as? Double ?? 0.65 {
        didSet { UserDefaults.standard.set(wordPause, forKey: "wordPause") }
    }
    @Published var rate: Double = UserDefaults.standard.object(forKey: "rate") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(rate, forKey: "rate") }
    }
    @Published var sentencePause: Double = UserDefaults.standard.object(forKey: "sentencePause") as? Double ?? 0.85 {
        didSet { UserDefaults.standard.set(sentencePause, forKey: "sentencePause") }
    }
    var rateLabel: String {
        switch rate {
        case 0.0: return "Muy lenta"
        case 0.25: return "Lenta"
        case 0.4: return "Media"
        case 0.5: return "Normal"
        case 0.6: return "Rápida"
        default: return "Personalizada"
        }
    }
    @Published var highlight = UserDefaults.standard.object(forKey: "highlight") as? Bool ?? true {
        didSet { UserDefaults.standard.set(highlight, forKey: "highlight") }
    }
    @Published var magnify = UserDefaults.standard.object(forKey: "magnify") as? Bool ?? true {
        didSet { UserDefaults.standard.set(magnify, forKey: "magnify") }
    }
    @Published var wordBandAtTop = UserDefaults.standard.bool(forKey: "wordBandAtTop") {
        didSet { UserDefaults.standard.set(wordBandAtTop, forKey: "wordBandAtTop") }
    }
    @Published var scale: Double = UserDefaults.standard.object(forKey: "scale") as? Double ?? 1.5 {
        didSet { UserDefaults.standard.set(scale, forKey: "scale") }
    }
    @Published var voiceEnabled = UserDefaults.standard.object(forKey: "voiceEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voiceEnabled, forKey: "voiceEnabled"); stop() }
    }
    @Published var voiceID = UserDefaults.standard.string(forKey: "voice") ?? "" {
        didSet { UserDefaults.standard.set(voiceID, forKey: "voice"); if playing || paused { speak() } }
    }
    private var synth = AVSpeechSynthesizer()
    private var active: [AVSpeechUtterance] = []
    private var speechOffsets: [ObjectIdentifier: Int] = [:]
    private var interruption: NSObjectProtocol?
    var sentence: Sentence? { sentences.indices.contains(index) ? sentences[index] : nil }
    var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var voices: [AVSpeechSynthesisVoice] { AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("es-") }.sorted { $0.language + $0.name < $1.language + $1.name } }

    override init() {
        super.init()
        // Keep the previously selected slowest preset at its new minimum.
        if rate == 0.1 { rate = Double(AVSpeechUtteranceMinimumSpeechRate) }
        synth.delegate = self
        refresh()
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.pause() }
        }
    }
    func refresh() {
        let hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenDocuments") ?? [])
        var imported = UserDefaults.standard.dictionary(forKey: "documentImportDates") as? [String: Double] ?? [:]
        let urls = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "pdf" }
        // Existing documents use file dates until an explicit import date is available.
        for url in urls where imported[url.lastPathComponent] == nil {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            imported[url.lastPathComponent] = (values?.creationDate ?? values?.contentModificationDate ?? .distantPast).timeIntervalSince1970
        }
        UserDefaults.standard.set(imported, forKey: "documentImportDates")
        files = urls.filter { !hidden.contains($0.lastPathComponent) }.sorted {
            let lhs = imported[$0.lastPathComponent] ?? 0
            let rhs = imported[$1.lastPathComponent] ?? 0
            return lhs == rhs ? $0.lastPathComponent < $1.lastPathComponent : lhs > rhs
        }
    }
    private func recordImport(_ url: URL) {
        var imported = UserDefaults.standard.dictionary(forKey: "documentImportDates") as? [String: Double] ?? [:]
        imported[url.lastPathComponent] = Date().timeIntervalSince1970
        UserDefaults.standard.set(imported, forKey: "documentImportDates")
        let hidden = (UserDefaults.standard.stringArray(forKey: "hiddenDocuments") ?? []).filter { $0 != url.lastPathComponent }
        UserDefaults.standard.set(hidden, forKey: "hiddenDocuments")
    }
    func importPDF(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = url.deletingPathExtension().lastPathComponent
            var destination = directory.appendingPathComponent(name).appendingPathExtension("pdf")
            if FileManager.default.fileExists(atPath: destination.path) { destination = directory.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6)).pdf") }
            try FileManager.default.copyItem(at: url, to: destination)
            recordImport(destination)
            refresh(); open(destination)
        } catch { message = "No se pudo importar el PDF: \(error.localizedDescription)" }
    }
    func hideDocument(_ url: URL) {
        if currentURL == url { close() }
        var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenDocuments") ?? [])
        hidden.insert(url.lastPathComponent)
        UserDefaults.standard.set(Array(hidden), forKey: "hiddenDocuments")
        refresh()
    }
    func open(_ url: URL) {
        close()
        guard let pdf = PDFDocument(url: url), !pdf.isLocked else { message = "No se puede abrir este PDF. Puede estar protegido o dañado."; return }
        document = pdf; currentURL = url; loading = true
        progress.beginDocument(fileKey: url.lastPathComponent, title: title(for: url))
        hasStartedReading = false
        // Yield between pages so large documents do not monopolize the main thread.
        Task { @MainActor in
            var result: [Sentence] = []
            for pageIndex in 0..<pdf.pageCount {
                guard currentURL == url, document === pdf else { return }
                let page = pdf.page(at: pageIndex)
                let original = page?.string ?? ""
                var footerRanges: [NSRange] = []
                if let page {
                    let pageBounds = page.bounds(for: .cropBox)
                    original.enumerateSubstrings(in: original.startIndex..<original.endIndex, options: .byLines) { line, range, _, _ in
                        let label = (line ?? "").trimmingCharacters(in: .whitespaces)
                        guard label.range(of: #"^[0-9]{1,5}$"#, options: .regularExpression) != nil else { return }
                        let sourceRange = NSRange(range, in: original)
                        guard let selection = page.selection(for: sourceRange) else { return }
                        let bounds = selection.bounds(for: page)
                        // PDF coordinates grow upwards: use the visual bottom margin.
                        let rotation = ((page.rotation % 360) + 360) % 360
                        let isFooter: Bool
                        switch rotation {
                        case 0: isFooter = bounds.midY < pageBounds.minY + pageBounds.height * 0.12
                        case 180: isFooter = bounds.midY > pageBounds.maxY - pageBounds.height * 0.12
                        default: isFooter = false // Avoid guessing on rotated layouts.
                        }
                        if isFooter { footerRanges.append(sourceRange) }
                    }
                }
                let text = ReadingStructure.maskedText(original, excluding: footerRanges)
                let attributed = page?.attributedString
                var sizes: [CGFloat] = []
                if let attributed {
                    attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                        if let font = value as? UIFont { sizes.append(contentsOf: repeatElement(font.pointSize, count: range.length)) }
                    }
                }
                let sortedSizes = sizes.sorted()
                let bodySize = sortedSizes.isEmpty ? CGFloat(0) : sortedSizes[sortedSizes.count / 2]
                let parts = ReadingStructure.index(text: text) { range in
                    guard let attributed, NSMaxRange(range) <= attributed.length, bodySize > 0 else { return false }
                    var large = false
                    attributed.enumerateAttribute(.font, in: range) { value, _, _ in
                        if let font = value as? UIFont, font.pointSize > bodySize * 1.15 { large = true }
                    }
                    return large
                }
                for part in parts {
                    result.append(Sentence(id: result.count, page: pageIndex, range: part.range,
                        text: (text as NSString).substring(with: part.range), pauseBefore: part.pause))
                }
                await Task.yield()
            }
            guard currentURL == url, document === pdf else { return }
            buildChapters(pdf)
            sentences = result
            index = min(max(0, UserDefaults.standard.integer(forKey: progressKey(url))), max(0, result.count - 1))
            loading = false
            if result.isEmpty { message = "Este PDF no contiene texto seleccionable. El reconocimiento de escaneos estará disponible en una próxima versión." }
        }
    }
    private func buildChapters(_ pdf: PDFDocument) {
        var entries: [ChapterEntry] = []
        func visit(_ node: PDFOutline, level: Int) {
            if let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination,
               let page = destination.page {
                let number = pdf.index(for: page)
                if number != NSNotFound {
                    entries.append(ChapterEntry(title: node.label ?? "Sección", page: number,
                        level: level, destination: destination, sourceRange: nil))
                }
            }
            for i in 0..<node.numberOfChildren {
                if let child = node.child(at: i) { visit(child, level: level + 1) }
            }
        }
        if let root = pdf.outlineRoot {
            for i in 0..<root.numberOfChildren {
                if let child = root.child(at: i) { visit(child, level: 0) }
            }
        }
        inferredChapters = entries.isEmpty
        if entries.isEmpty {
            // Conservative fallback: complete lines beginning with a chapter label.
            let pattern = #"(?im)^[ \t]*(?:(?:cap[ií]tulo|chapter|parte|secci[oó]n)[ \t]+[^\r\n]{1,100}|[0-9]{1,3}[ \t]*\r?\n(?:[ \t]*[0-9]{1,3}[ \t]*\r?\n)?[ \t]*[^\W\d_][^\r\n]{1,99}(?=\r?$))"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                for number in 0..<pdf.pageCount {
                    let text = pdf.page(at: number)?.string ?? ""
                    for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                        let title = (text as NSString).substring(with: match.range).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
                        entries.append(ChapterEntry(title: title, page: number, level: 0, destination: nil, sourceRange: match.range))
                    }
                }
            }
        }
        chapters = entries
    }
    func goToChapter(_ chapter: ChapterEntry) {
        guard let pdf = document, let page = pdf.page(at: chapter.page) else { return }
        stop()
        let character = chapter.sourceRange?.location ?? chapter.destination.map { page.characterIndex(at: $0.point) }
        if let target = sentences.firstIndex(where: {
            sentence in
            sentence.page == chapter.page && character.map { NSLocationInRange($0, sentence.range) } == true
        }) { index = target }
        else if let target = sentences.firstIndex(where: { $0.page == chapter.page }) { index = target }
        save()
        if let destination = chapter.destination { chapterJump = ChapterJump(destination: destination) }
        else if let range = chapter.sourceRange, let selection = page.selection(for: range) {
            let bounds = selection.bounds(for: page)
            chapterJump = ChapterJump(destination: PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: bounds.maxY)))
        } else {
            let bounds = page.bounds(for: .cropBox)
            chapterJump = ChapterJump(destination: PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: bounds.maxY)))
        }
    }
    func progressKey(_ url: URL) -> String { "progress.\(url.lastPathComponent)" }
    func save() { if let url = currentURL { UserDefaults.standard.set(index, forKey: progressKey(url)) } }
    func close() { save(); stop(); progress.finishDocument(); document = nil; currentURL = nil; sentences = []; chapters = []; chapterJump = nil; inferredChapters = false; index = 0; loading = false }
    func select(_ newIndex: Int, autoplay: Bool = true, initialDelay: Double = 0) {
        guard sentences.indices.contains(newIndex) else { return }
        index = newIndex; save()
        if autoplay && voiceEnabled { speak(initialDelay: initialDelay) }
        else if !manualReading { stop() }
    }
    func zoom(_ action: DocumentZoomAction) { zoomRequest = DocumentZoomRequest(action: action) }
    func step(_ delta: Int) { select(index + delta) }
    func stop() {
        progress.pause()
        manualReading = false
        active = []; speechOffsets = [:]
        // A cancelled/paused engine may finish cancellation asynchronously.
        // Give the new sentence its own engine so it cannot inherit that state.
        synth.delegate = nil
        synth.stopSpeaking(at: .immediate)
        synth = AVSpeechSynthesizer()
        synth.delegate = self
        playing = false; paused = false; word = ""; wordRange = nil
    }
    func pause() {
        progress.pause()
        manualReading = false
        guard playing else { return }
        if synth.pauseSpeaking(at: .immediate) { playing = false; paused = true }
        else { stop() }
    }
    func toggle() {
        if synth.isPaused {
            if synth.continueSpeaking() {
                paused = false; playing = true
                if !word.isEmpty { progress.start(mode: "voice") }
            }
            else { speak() }
        } else if playing && synth.isSpeaking { pause() }
        else { speak() }
    }
    func toggleManualReading() {
        guard !voiceEnabled, sentence != nil, !loading else { return }
        manualReading.toggle()
        if manualReading { progress.start(mode: "manual") }
        else { progress.pause() }
    }
    func speak(initialDelay: Double = 0) {
        guard voiceEnabled, let sentence else { return }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { message = "No se pudo iniciar el audio: \(error.localizedDescription)"; return }
        // Never leave voice nil: the device default may be English.
        let installed = voices
        let selected = installed.first { $0.identifier == voiceID }
        let latinLanguages = ["es-AR", "es-MX", "es-419", "es-CO", "es-CL", "es-US"]
        let automatic = latinLanguages.lazy.compactMap { language in
            installed.filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
                .sorted { $0.quality.rawValue > $1.quality.rawValue }.first
        }.first ?? installed.first { $0.language != "es-ES" }
        guard let voice = selected ?? automatic else {
            message = "No hay una voz de español latino disponible. Instalá una voz de Español (México) en Ajustes del iPad → Accesibilidad → Contenido leído → Voces. Después volvé a abrir Lulexia."
            return
        }
        // Preserve source offsets, including punctuation and line breaks.
        let text = sentence.text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let source = text as NSString
        var boundaries = [0]
        if stepByStep {
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, _ in
                let location = NSRange(range, in: text).location
                if location > 0 { boundaries.append(location) }
            }
            // Keep opening punctuation with the first word.
            if boundaries.count > 1,
               source.substring(to: boundaries[1]).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).isEmpty {
                boundaries.remove(at: 1)
            }
        }
        boundaries.append(source.length)
        active = zip(boundaries, boundaries.dropFirst()).enumerated().map { position, bounds in
            let fragment = source.substring(with: NSRange(location: bounds.0, length: bounds.1 - bounds.0))
            // Isolated Spanish "y" may be spelled out as "y griega".
            // A one-character phonetic substitution preserves highlighting offsets.
            let spoken = stepByStep ? fragment.replacingOccurrences(of: #"\b[yY]\b"#, with: "i", options: .regularExpression) : fragment
            let utterance = AVSpeechUtterance(string: spoken)
            utterance.rate = stepByStep ? AVSpeechUtteranceMinimumSpeechRate : max(AVSpeechUtteranceMinimumSpeechRate, Float(min(0.6, rate)))
            utterance.voice = voice
            utterance.preUtteranceDelay = position == 0 ? initialDelay : wordPause
            speechOffsets[ObjectIdentifier(utterance)] = bounds.0
            return utterance
        }
        hasStartedReading = true
        playing = true
        for utterance in active { synth.speak(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard synthesizer === self.synth, let offset = self.speechOffsets[ObjectIdentifier(utterance)], let sentence = self.sentence else { return }
            let mapped = NSRange(location: offset + range.location, length: range.length)
            guard NSMaxRange(mapped) <= (sentence.text as NSString).length else { return }
            if self.playing && !self.paused { self.progress.start(mode: "voice") }
            self.word = (sentence.text as NSString).substring(with: mapped)
            self.wordRange = NSRange(location: sentence.range.location + mapped.location, length: mapped.length)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard synthesizer === self.synth, self.active.contains(where: { $0 === utterance }) else { return }
            self.progress.pause()
            guard self.active.last === utterance else { return }
            if self.index + 1 < self.sentences.count {
                let structuralPause = max(0, self.sentences[self.index + 1].pauseBefore - 0.85)
                self.select(self.index + 1, initialDelay: self.sentencePause + structuralPause)
            } else { self.stop() }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard synthesizer === self.synth, self.active.last === utterance else { return }
            self.progress.pause()
            self.active = []; self.speechOffsets = [:]
            self.playing = false; self.paused = false
            self.word = ""; self.wordRange = nil
        }
    }
    func createSample() {
        let url = directory.appendingPathComponent("Bienvenida a Lulexia.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                let text = "Bienvenida a Lulexia\n\nCada persona tiene su propio ritmo de lectura. Podés tocar una oración para escucharla.\n\nLas palabras se iluminan mientras avanza la voz. Probá pausar y continuar cuando lo necesites.\n\nTambién podés cambiar la velocidad de lectura con los botones de la barra inferior.\n\nLeer con calma permite descubrir nuevas ideas. ¿Comenzamos otra vez?"
                (text as NSString).draw(in: CGRect(x: 55, y: 65, width: 485, height: 710), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black])
            }
            recordImport(url)
            refresh(); open(url)
        } catch { message = error.localizedDescription }
    }
}

// Structural breaks are separate from ordinary PDF line wrapping.
enum ReadingStructure {
    // Spaces preserve every UTF-16 source offset used for word highlighting.
    static func maskedText(_ text: String, excluding ranges: [NSRange]) -> String {
        let result = NSMutableString(string: text)
        for range in ranges where range.location >= 0 && NSMaxRange(range) <= result.length {
            result.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return result as String
    }
    struct Part { let range: NSRange; let pause: Double }
    static func index(text: String, isLarge: (NSRange) -> Bool = { _ in false }) -> [Part] {
        let source = text as NSString
        var lines: [(range: NSRange, end: Int, text: String)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byLines) { value, range, enclosing, _ in
            lines.append((NSRange(range, in: text), NSMaxRange(NSRange(enclosing, in: text)), value ?? ""))
        }
        var breaks: [Int: Double] = [0: 0.85, source.length: 0.85]
        for (i, line) in lines.enumerated() {
            let clean = line.text.trimmingCharacters(in: .whitespaces)
            if clean.isEmpty { breaks[line.end] = max(breaks[line.end] ?? 0, 1.1); continue }
            let dialogue = clean.hasPrefix("--") || clean.hasPrefix("—") || clean.hasPrefix("–")
            if dialogue { breaks[line.range.location] = max(breaks[line.range.location] ?? 0, 1.1) }
            let short = clean.count <= 100 && clean.split(separator: " ").count <= 14
            let noEnding = !".!?;:,…”.»".contains(clean.last!)
            let gap = i + 1 < lines.count ? source.substring(with: NSRange(location: NSMaxRange(line.range), length: max(0, lines[i + 1].range.location - NSMaxRange(line.range)))) : ""
            let nextBlank = i + 1 < lines.count && lines[i + 1].text.trimmingCharacters(in: .whitespaces).isEmpty
            let isolated = nextBlank || gap.replacingOccurrences(of: "\r\n", with: "\n").filter { $0 == "\n" || $0 == "\r" }.count >= 2
            // Font evidence or an isolated, short, unpunctuated line indicates a title.
            if !dialogue && short && noEnding && (isLarge(line.range) || isolated) {
                breaks[line.range.location] = max(breaks[line.range.location] ?? 0, 1.1)
                breaks[line.end] = max(breaks[line.end] ?? 0, 1.4)
            }
        }
        let positions = breaks.keys.sorted()
        var result: [Part] = []
        var pendingPause = 0.85
        for (start, end) in zip(positions, positions.dropFirst()) {
            guard end > start else { continue }
            pendingPause = max(pendingPause, breaks[start]!)
            let block = source.substring(with: NSRange(location: start, length: end - start))
            let normalized = block.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.setLanguage(.spanish)
            tokenizer.string = normalized
            var first = true
            tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
                let local = NSRange(range, in: normalized)
                if !(normalized as NSString).substring(with: local).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(Part(range: NSRange(location: start + local.location, length: local.length), pause: first ? pendingPause : 0.85))
                    first = false
                }
                return true
            }
            if !first { pendingPause = 0.85 }
        }
        return result
    }
}
