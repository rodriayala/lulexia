import Foundation
import NaturalLanguage

@main struct ReadingStructureChecks {
    static func main() {
        func parts(_ text: String) -> [(String, Double)] {
            ReadingStructure.index(text: text).map { ((text as NSString).substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines), $0.pause) }
        }
        let title = parts("El encuentro\n\nUna mañana, Ana salió a caminar.")
        precondition(title.count == 2 && title[0].0 == "El encuentro" && title[1].1 >= 1.4)
        let dialogue = parts("-- Hola, ¿cómo estás?\n-- Muy bien, gracias.")
        precondition(dialogue.count == 2 && dialogue[1].0.hasPrefix("--") && dialogue[1].1 >= 1.1)
        let wrapped = parts("Esta oración continúa\nen el siguiente renglón, sin cortarse.")
        precondition(wrapped.count == 1)
        let fontTitle = "Un título\nUna oración completa."
        let detected = ReadingStructure.index(text: fontTitle, isLarge: { $0.location == 0 })
        precondition(detected.count == 2 && detected[1].pause >= 1.4)
        let unicode = "Título 📚\r\n\r\n— ¡Sí, mañana!\r\n— Adiós."
        let mapped = parts(unicode)
        precondition(mapped.count == 3 && mapped[1].0.contains("Sí") && mapped[2].0 == "— Adiós.")
        let footerSource = "8\nTítulo 📚\nTexto con el número 42.\n123"
        let footerRange = (footerSource as NSString).range(of: "123", options: .backwards)
        let filtered = ReadingStructure.maskedText(footerSource, excluding: [footerRange])
        precondition((filtered as NSString).length == (footerSource as NSString).length)
        precondition(filtered.hasPrefix("8\n") && filtered.contains("número 42.") && !filtered.contains("123"))
        precondition((filtered as NSString).range(of: "Texto").location == (footerSource as NSString).range(of: "Texto").location)
        print("6 comprobaciones de estructura y rangos UTF-16 correctas")
    }
}
