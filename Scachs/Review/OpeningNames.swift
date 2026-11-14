import Foundation

/// Lichess names openings in English. This reads them in Catalan or Spanish by rule, not by a table of four thousand lines:
/// the kind of line (defence, gambit, variation) goes first, then what describes it, then whose it is.
/// "King's Gambit Accepted: Hanstein Gambit" → "Gambit de rei acceptat: gambit Hanstein". Names it can't read stay as they are.
enum OpeningNames {
    static func local(_ english: String, language: String? = Locale.current.language.languageCode?.identifier) -> String {
        guard let lang = language, let dict = Dict.all[lang] else { return english }
        if let whole = dict.whole[english] { return whole }
        let (head, rest) = split(english)
        var out = capitalized(dict.whole[head] ?? segment(head, dict))
        if let rest {
            out += ": " + rest.components(separatedBy: ", ").map { segment($0, dict) }.joined(separator: ", ")
        }
        return out
    }

    private static func split(_ s: String) -> (String, String?) {
        guard let i = s.firstIndex(of: ":") else { return (s, nil) }
        return (String(s[..<i]), s[s.index(after: i)...].trimmingCharacters(in: .whitespaces))
    }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// One part of a name, e.g. "Two Knights Variation" → "variant dels dos cavalls".
    static func segment(_ text: String, _ d: Dict) -> String {
        var words = text.split(separator: " ").map(String.init)
        if words.first == "with" { return ([d.with] + words.dropFirst()).joined(separator: " ") }
        var modifier: Kind.Modifier?
        if let last = words.last, let m = Kind.Modifier(rawValue: last), words.count > 1, Kind.types[words[words.count - 2]] != nil {
            modifier = m; words.removeLast()
        }
        guard let last = words.last, let kind = Kind.types[last], let type = d.types[kind] else { return text }
        words.removeLast()
        var adjectives: [String] = [], names: [String] = [], phrases: [String] = []
        var i = 0
        while i < words.count {
            if i + 1 < words.count, let p = d.phrases[words[i] + " " + words[i + 1]] { phrases.append(p); i += 2; continue }
            if let p = d.phrases[words[i]] { phrases.append(p) }
            else if let a = d.adjectives[words[i]] { adjectives.append(type.feminine ? a.f : a.m) }
            else { names.append(words[i]) }
            i += 1
        }
        var parts = [type.word] + adjectives + names + phrases
        if let modifier, let m = d.modifiers[modifier] { parts.append(type.feminine ? m.f : m.m) }
        return parts.joined(separator: " ")
    }

    enum Kind: String {
        case variation, gambit, countergambit, defense, attack, counterattack, line, system, opening, game, formation, trap
        enum Modifier: String { case accepted = "Accepted", declined = "Declined", deferred = "Deferred" }
        static let types: [String: Kind] = ["Variation": .variation, "Gambit": .gambit, "Countergambit": .countergambit, "Defense": .defense,
                                            "Attack": .attack, "Counterattack": .counterattack, "Line": .line, "System": .system,
                                            "Opening": .opening, "Game": .game, "Formation": .formation, "Trap": .trap]
    }

    struct Dict {
        let types: [Kind: (word: String, feminine: Bool)]
        let modifiers: [Kind.Modifier: (m: String, f: String)]
        let adjectives: [String: (m: String, f: String)]
        let phrases: [String: String]
        let whole: [String: String]
        let with: String

        static let all = ["ca": ca, "es": es]

        static let ca = Dict(
            types: [.variation: ("variant", true), .gambit: ("gambit", false), .countergambit: ("contragambit", false), .defense: ("defensa", true),
                    .attack: ("atac", false), .counterattack: ("contraatac", false), .line: ("línia", true), .system: ("sistema", false),
                    .opening: ("obertura", true), .game: ("partida", true), .formation: ("formació", true), .trap: ("parany", false)],
            modifiers: [.accepted: ("acceptat", "acceptada"), .declined: ("refusat", "refusada"), .deferred: ("diferit", "diferida")],
            adjectives: ["Sicilian": ("sicilià", "siciliana"), "French": ("francès", "francesa"), "Italian": ("italià", "italiana"),
                         "English": ("anglès", "anglesa"), "Indian": ("indi", "índia"), "Dutch": ("holandès", "holandesa"),
                         "Slav": ("eslau", "eslava"), "Semi-Slav": ("semieslau", "semieslava"), "Scotch": ("escocès", "escocesa"),
                         "Scandinavian": ("escandinau", "escandinava"), "Modern": ("modern", "moderna"), "Classical": ("clàssic", "clàssica"),
                         "Closed": ("tancat", "tancada"), "Open": ("obert", "oberta"), "Main": ("principal", "principal"),
                         "Normal": ("normal", "normal"), "Orthodox": ("ortodox", "ortodoxa"), "Symmetrical": ("simètric", "simètrica"),
                         "Reversed": ("invertit", "invertida"), "Accelerated": ("accelerat", "accelerada"), "Polish": ("polonès", "polonesa"),
                         "Catalan": ("català", "catalana"), "Vienna": ("vienès", "vienesa"), "Latvian": ("letó", "letona"),
                         "Danish": ("danès", "danesa"), "Old": ("antic", "antiga"), "Berlin": ("berlinès", "berlinesa"),
                         "Spanish": ("espanyol", "espanyola"), "Hungarian": ("hongarès", "hongaresa"), "Portuguese": ("portuguès", "portuguesa"),
                         "Mexican": ("mexicà", "mexicana"), "Czech": ("txec", "txeca"), "Irish": ("irlandès", "irlandesa"),
                         "Australian": ("australià", "australiana"), "Nimzo-Indian": ("nimzoindi", "nimzoíndia"),
                         "Bogo-Indian": ("bogoindi", "bogoíndia"), "Anglo-Indian": ("angloindi", "angloíndia"), "Anglo-Slav": ("angloeslau", "angloeslava"),
                         "Quiet": ("tranquil", "tranquil·la"), "Traditional": ("tradicional", "tradicional"), "Positional": ("posicional", "posicional"),
                         "Delayed": ("retardat", "retardada"), "Double": ("doble", "doble"), "Semi-Open": ("semiobert", "semioberta")],
            phrases: ["King's": "de rei", "Queen's": "de dama", "Bishop's": "de l'alfil", "King's Pawn": "del peó de rei",
                      "Queen's Pawn": "del peó de dama", "King's Knight": "del cavall de rei", "Two Knights": "dels dos cavalls",
                      "Three Knights": "dels tres cavalls", "Four Knights": "dels quatre cavalls", "Four Pawns": "dels quatre peons",
                      "Exchange": "del canvi", "Advance": "de l'avanç", "Fianchetto": "del fianchetto", "Dragon": "del drac",
                      "Center": "del centre", "Wing": "de l'ala", "Elephant": "de l'elefant", "Lion": "del lleó", "Rat": "de la rata",
                      "Hippopotamus": "de l'hipopòtam", "Kangaroo": "del cangur", "Pterodactyl": "del pterodàctil"],
            whole: ["Ruy Lopez": "Obertura espanyola", "Giuoco Piano": "Giuoco piano"],
            with: "amb")

        static let es = Dict(
            types: [.variation: ("variante", true), .gambit: ("gambito", false), .countergambit: ("contragambito", false), .defense: ("defensa", true),
                    .attack: ("ataque", false), .counterattack: ("contraataque", false), .line: ("línea", true), .system: ("sistema", false),
                    .opening: ("apertura", true), .game: ("partida", true), .formation: ("formación", true), .trap: ("trampa", true)],
            modifiers: [.accepted: ("aceptado", "aceptada"), .declined: ("rehusado", "rehusada"), .deferred: ("diferido", "diferida")],
            adjectives: ["Sicilian": ("siciliano", "siciliana"), "French": ("francés", "francesa"), "Italian": ("italiano", "italiana"),
                         "English": ("inglés", "inglesa"), "Indian": ("indio", "india"), "Dutch": ("holandés", "holandesa"),
                         "Slav": ("eslavo", "eslava"), "Semi-Slav": ("semieslavo", "semieslava"), "Scotch": ("escocés", "escocesa"),
                         "Scandinavian": ("escandinavo", "escandinava"), "Modern": ("moderno", "moderna"), "Classical": ("clásico", "clásica"),
                         "Closed": ("cerrado", "cerrada"), "Open": ("abierto", "abierta"), "Main": ("principal", "principal"),
                         "Normal": ("normal", "normal"), "Orthodox": ("ortodoxo", "ortodoxa"), "Symmetrical": ("simétrico", "simétrica"),
                         "Reversed": ("invertido", "invertida"), "Accelerated": ("acelerado", "acelerada"), "Polish": ("polaco", "polaca"),
                         "Catalan": ("catalán", "catalana"), "Vienna": ("vienés", "vienesa"), "Latvian": ("letón", "letona"),
                         "Danish": ("danés", "danesa"), "Old": ("antiguo", "antigua"), "Berlin": ("berlinés", "berlinesa"),
                         "Spanish": ("español", "española"), "Hungarian": ("húngaro", "húngara"), "Portuguese": ("portugués", "portuguesa"),
                         "Mexican": ("mexicano", "mexicana"), "Czech": ("checo", "checa"), "Irish": ("irlandés", "irlandesa"),
                         "Australian": ("australiano", "australiana"), "Nimzo-Indian": ("nimzoindio", "nimzoindia"),
                         "Bogo-Indian": ("bogoindio", "bogoindia"), "Anglo-Indian": ("angloindio", "angloindia"), "Anglo-Slav": ("angloeslavo", "angloeslava"),
                         "Quiet": ("tranquilo", "tranquila"), "Traditional": ("tradicional", "tradicional"), "Positional": ("posicional", "posicional"),
                         "Delayed": ("retrasado", "retrasada"), "Double": ("doble", "doble"), "Semi-Open": ("semiabierto", "semiabierta")],
            phrases: ["King's": "de rey", "Queen's": "de dama", "Bishop's": "del alfil", "King's Pawn": "de peón de rey",
                      "Queen's Pawn": "de peón de dama", "King's Knight": "del caballo de rey", "Two Knights": "de los dos caballos",
                      "Three Knights": "de los tres caballos", "Four Knights": "de los cuatro caballos", "Four Pawns": "de los cuatro peones",
                      "Exchange": "del cambio", "Advance": "del avance", "Fianchetto": "del fianchetto", "Dragon": "del dragón",
                      "Center": "del centro", "Wing": "del ala", "Elephant": "del elefante", "Lion": "del león", "Rat": "de la rata",
                      "Hippopotamus": "del hipopótamo", "Kangaroo": "del canguro", "Pterodactyl": "del pterodáctilo"],
            whole: ["Ruy Lopez": "Apertura española", "Giuoco Piano": "Giuoco piano"],
            with: "con")
    }
}
