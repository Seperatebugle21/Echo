import Foundation

/// Parses only bounded, complete audio commands, independently of the app language.
struct EchoSpokenCommand: Equatable {
    enum Language: String, CaseIterable { case en, nl, fr, de }
    enum Action: Equatable {
        case flow, flowCurrent, stopFlow, favorite, unfavorite, shuffleOn, shuffleOff
        case repeatOne, repeatAll, repeatOff, pause, resume, next, previous, status, cancelSleep
        case sleep(Int)
    }
    let action: Action
    let language: Language
    private struct Entry {
        let action: Action
        let language: Language
        let phrase: String
    }
    private static let entries: [Entry] = [
        Entry(action: .flow, language: .en, phrase: "start flow"),
        Entry(action: .flow, language: .en, phrase: "start the flow"),
        Entry(action: .flow, language: .en, phrase: "start echo flow"),
        Entry(action: .flow, language: .nl, phrase: "start de flow"),
        Entry(action: .flow, language: .nl, phrase: "start flow"),
        Entry(action: .flow, language: .nl, phrase: "begin de flow"),
        Entry(action: .flow, language: .nl, phrase: "zet flow aan"),
        Entry(action: .flow, language: .fr, phrase: "lance le flow"),
        Entry(action: .flow, language: .fr, phrase: "demarre le flow"),
        Entry(action: .flow, language: .fr, phrase: "active le flow"),
        Entry(action: .flow, language: .de, phrase: "starte flow"),
        Entry(action: .flow, language: .de, phrase: "starte den flow"),
        Entry(action: .flow, language: .de, phrase: "flow starten"),
        Entry(action: .flowCurrent, language: .en, phrase: "start flow from this song"),
        Entry(action: .flowCurrent, language: .en, phrase: "start the flow with this song"),
        Entry(action: .flowCurrent, language: .en, phrase: "flow from this song"),
        Entry(action: .flowCurrent, language: .nl, phrase: "start de flow uit dit liedje"),
        Entry(action: .flowCurrent, language: .nl, phrase: "start de flow met dit nummer"),
        Entry(action: .flowCurrent, language: .nl, phrase: "start flow met dit liedje"),
        Entry(action: .flowCurrent, language: .nl, phrase: "flow vanuit dit nummer"),
        Entry(action: .flowCurrent, language: .fr, phrase: "lance le flow avec ce morceau"),
        Entry(action: .flowCurrent, language: .fr, phrase: "demarre le flow a partir de cette chanson"),
        Entry(action: .flowCurrent, language: .de, phrase: "starte flow mit diesem lied"),
        Entry(action: .flowCurrent, language: .de, phrase: "starte den flow mit diesem titel"),
        Entry(action: .stopFlow, language: .en, phrase: "stop flow"),
        Entry(action: .stopFlow, language: .en, phrase: "stop the flow"),
        Entry(action: .stopFlow, language: .en, phrase: "turn flow off"),
        Entry(action: .stopFlow, language: .nl, phrase: "stop de flow"),
        Entry(action: .stopFlow, language: .nl, phrase: "stop flow"),
        Entry(action: .stopFlow, language: .nl, phrase: "zet flow uit"),
        Entry(action: .stopFlow, language: .fr, phrase: "arrete le flow"),
        Entry(action: .stopFlow, language: .fr, phrase: "desactive le flow"),
        Entry(action: .stopFlow, language: .de, phrase: "stoppe flow"),
        Entry(action: .stopFlow, language: .de, phrase: "flow ausschalten"),
        Entry(action: .favorite, language: .en, phrase: "favorite this song"),
        Entry(action: .favorite, language: .en, phrase: "favourite this song"),
        Entry(action: .favorite, language: .en, phrase: "favorite this"),
        Entry(action: .favorite, language: .en, phrase: "like this song"),
        Entry(action: .favorite, language: .en, phrase: "add this song to favorites"),
        Entry(action: .favorite, language: .en, phrase: "save this song to favorites"),
        Entry(action: .favorite, language: .nl, phrase: "maak dit liedje favoriet"),
        Entry(action: .favorite, language: .nl, phrase: "maak dit nummer favoriet"),
        Entry(action: .favorite, language: .nl, phrase: "dit liedje favoriet"),
        Entry(action: .favorite, language: .nl, phrase: "voeg dit liedje toe aan favorieten"),
        Entry(action: .favorite, language: .nl, phrase: "favoriet dit nummer"),
        Entry(action: .favorite, language: .fr, phrase: "ajoute ce morceau aux favoris"),
        Entry(action: .favorite, language: .fr, phrase: "ajoute cette chanson aux favoris"),
        Entry(action: .favorite, language: .fr, phrase: "mets ce titre en favori"),
        Entry(action: .favorite, language: .de, phrase: "markiere dieses lied als favorit"),
        Entry(action: .favorite, language: .de, phrase: "fuge dieses lied zu favoriten hinzu"),
        Entry(action: .favorite, language: .de, phrase: "diesen titel favorisieren"),
        Entry(action: .unfavorite, language: .en, phrase: "unfavorite this song"),
        Entry(action: .unfavorite, language: .en, phrase: "unfavourite this song"),
        Entry(action: .unfavorite, language: .en, phrase: "remove this song from favorites"),
        Entry(action: .unfavorite, language: .nl, phrase: "verwijder dit liedje uit favorieten"),
        Entry(action: .unfavorite, language: .nl, phrase: "haal dit nummer uit favorieten"),
        Entry(action: .unfavorite, language: .fr, phrase: "retire ce morceau des favoris"),
        Entry(action: .unfavorite, language: .fr, phrase: "supprime cette chanson des favoris"),
        Entry(action: .unfavorite, language: .de, phrase: "entferne dieses lied aus den favoriten"),
        Entry(action: .unfavorite, language: .de, phrase: "diesen titel nicht mehr favorisieren"),
        Entry(action: .shuffleOn, language: .en, phrase: "shuffle"),
        Entry(action: .shuffleOn, language: .en, phrase: "shuffle this song"),
        Entry(action: .shuffleOn, language: .en, phrase: "turn shuffle on"),
        Entry(action: .shuffleOn, language: .en, phrase: "enable shuffle"),
        Entry(action: .shuffleOn, language: .nl, phrase: "shuffle dit liedje"),
        Entry(action: .shuffleOn, language: .nl, phrase: "shuffle dit nummer"),
        Entry(action: .shuffleOn, language: .nl, phrase: "zet shuffle aan"),
        Entry(action: .shuffleOn, language: .nl, phrase: "shuffle aan"),
        Entry(action: .shuffleOn, language: .fr, phrase: "active le mode aleatoire"),
        Entry(action: .shuffleOn, language: .fr, phrase: "lecture aleatoire"),
        Entry(action: .shuffleOn, language: .fr, phrase: "melange les titres"),
        Entry(action: .shuffleOn, language: .de, phrase: "zufallswiedergabe einschalten"),
        Entry(action: .shuffleOn, language: .de, phrase: "shuffle einschalten"),
        Entry(action: .shuffleOn, language: .de, phrase: "mische die lieder"),
        Entry(action: .shuffleOff, language: .en, phrase: "turn shuffle off"),
        Entry(action: .shuffleOff, language: .en, phrase: "disable shuffle"),
        Entry(action: .shuffleOff, language: .en, phrase: "shuffle off"),
        Entry(action: .shuffleOff, language: .nl, phrase: "zet shuffle uit"),
        Entry(action: .shuffleOff, language: .nl, phrase: "shuffle uit"),
        Entry(action: .shuffleOff, language: .fr, phrase: "desactive le mode aleatoire"),
        Entry(action: .shuffleOff, language: .fr, phrase: "arrete la lecture aleatoire"),
        Entry(action: .shuffleOff, language: .de, phrase: "zufallswiedergabe ausschalten"),
        Entry(action: .shuffleOff, language: .de, phrase: "shuffle ausschalten"),
        Entry(action: .repeatOne, language: .en, phrase: "repeat this song"),
        Entry(action: .repeatOne, language: .en, phrase: "repeat this track"),
        Entry(action: .repeatOne, language: .en, phrase: "loop this song"),
        Entry(action: .repeatOne, language: .nl, phrase: "herhaal dit liedje"),
        Entry(action: .repeatOne, language: .nl, phrase: "herhaal dit nummer"),
        Entry(action: .repeatOne, language: .nl, phrase: "dit liedje herhalen"),
        Entry(action: .repeatOne, language: .fr, phrase: "repete cette chanson"),
        Entry(action: .repeatOne, language: .fr, phrase: "repete ce morceau"),
        Entry(action: .repeatOne, language: .fr, phrase: "ce morceau en boucle"),
        Entry(action: .repeatOne, language: .de, phrase: "wiederhole dieses lied"),
        Entry(action: .repeatOne, language: .de, phrase: "wiederhole diesen titel"),
        Entry(action: .repeatOne, language: .de, phrase: "dieses lied wiederholen"),
        Entry(action: .repeatAll, language: .en, phrase: "repeat all"),
        Entry(action: .repeatAll, language: .en, phrase: "repeat the queue"),
        Entry(action: .repeatAll, language: .nl, phrase: "herhaal alles"),
        Entry(action: .repeatAll, language: .nl, phrase: "herhaal de wachtrij"),
        Entry(action: .repeatAll, language: .fr, phrase: "repete tout"),
        Entry(action: .repeatAll, language: .fr, phrase: "repete la file"),
        Entry(action: .repeatAll, language: .de, phrase: "alles wiederholen"),
        Entry(action: .repeatAll, language: .de, phrase: "wiederhole alle titel"),
        Entry(action: .repeatOff, language: .en, phrase: "stop repeating"),
        Entry(action: .repeatOff, language: .en, phrase: "turn repeat off"),
        Entry(action: .repeatOff, language: .en, phrase: "disable repeat"),
        Entry(action: .repeatOff, language: .nl, phrase: "stop herhalen"),
        Entry(action: .repeatOff, language: .nl, phrase: "zet herhalen uit"),
        Entry(action: .repeatOff, language: .nl, phrase: "herhalen uit"),
        Entry(action: .repeatOff, language: .fr, phrase: "arrete la repetition"),
        Entry(action: .repeatOff, language: .fr, phrase: "desactive la repetition"),
        Entry(action: .repeatOff, language: .de, phrase: "wiederholung ausschalten"),
        Entry(action: .repeatOff, language: .de, phrase: "stoppe die wiederholung"),
        Entry(action: .pause, language: .en, phrase: "pause"),
        Entry(action: .pause, language: .en, phrase: "pause music"),
        Entry(action: .pause, language: .en, phrase: "pause the music"),
        Entry(action: .pause, language: .en, phrase: "stop the music"),
        Entry(action: .pause, language: .nl, phrase: "pauze"),
        Entry(action: .pause, language: .nl, phrase: "pauzeer"),
        Entry(action: .pause, language: .nl, phrase: "pauzeer de muziek"),
        Entry(action: .pause, language: .nl, phrase: "stop de muziek"),
        Entry(action: .pause, language: .fr, phrase: "pause"),
        Entry(action: .pause, language: .fr, phrase: "mets la musique en pause"),
        Entry(action: .pause, language: .fr, phrase: "arrete la musique"),
        Entry(action: .pause, language: .de, phrase: "pause"),
        Entry(action: .pause, language: .de, phrase: "pausiere die musik"),
        Entry(action: .pause, language: .de, phrase: "musik pausieren"),
        Entry(action: .resume, language: .en, phrase: "resume"),
        Entry(action: .resume, language: .en, phrase: "resume music"),
        Entry(action: .resume, language: .en, phrase: "continue playing"),
        Entry(action: .resume, language: .nl, phrase: "hervat"),
        Entry(action: .resume, language: .nl, phrase: "hervat de muziek"),
        Entry(action: .resume, language: .nl, phrase: "speel verder"),
        Entry(action: .resume, language: .fr, phrase: "reprends la musique"),
        Entry(action: .resume, language: .fr, phrase: "reprends la lecture"),
        Entry(action: .resume, language: .fr, phrase: "continue la lecture"),
        Entry(action: .resume, language: .de, phrase: "musik fortsetzen"),
        Entry(action: .resume, language: .de, phrase: "setze die musik fort"),
        Entry(action: .resume, language: .de, phrase: "weiter abspielen"),
        Entry(action: .next, language: .en, phrase: "next"),
        Entry(action: .next, language: .en, phrase: "next song"),
        Entry(action: .next, language: .en, phrase: "next track"),
        Entry(action: .next, language: .en, phrase: "skip this song"),
        Entry(action: .next, language: .nl, phrase: "volgende"),
        Entry(action: .next, language: .nl, phrase: "volgend liedje"),
        Entry(action: .next, language: .nl, phrase: "volgend nummer"),
        Entry(action: .next, language: .nl, phrase: "sla dit liedje over"),
        Entry(action: .next, language: .fr, phrase: "suivant"),
        Entry(action: .next, language: .fr, phrase: "morceau suivant"),
        Entry(action: .next, language: .fr, phrase: "chanson suivante"),
        Entry(action: .next, language: .de, phrase: "weiter"),
        Entry(action: .next, language: .de, phrase: "nachster titel"),
        Entry(action: .next, language: .de, phrase: "nachstes lied"),
        Entry(action: .previous, language: .en, phrase: "previous"),
        Entry(action: .previous, language: .en, phrase: "previous song"),
        Entry(action: .previous, language: .en, phrase: "previous track"),
        Entry(action: .previous, language: .nl, phrase: "vorige"),
        Entry(action: .previous, language: .nl, phrase: "vorig liedje"),
        Entry(action: .previous, language: .nl, phrase: "vorig nummer"),
        Entry(action: .previous, language: .fr, phrase: "precedent"),
        Entry(action: .previous, language: .fr, phrase: "morceau precedent"),
        Entry(action: .previous, language: .fr, phrase: "chanson precedente"),
        Entry(action: .previous, language: .de, phrase: "vorheriger titel"),
        Entry(action: .previous, language: .de, phrase: "vorheriges lied"),
        Entry(action: .previous, language: .de, phrase: "zuruck"),
        Entry(action: .status, language: .en, phrase: "what is playing"),
        Entry(action: .status, language: .en, phrase: "whats playing"),
        Entry(action: .status, language: .en, phrase: "what song is this"),
        Entry(action: .status, language: .nl, phrase: "wat speelt er"),
        Entry(action: .status, language: .nl, phrase: "welk liedje is dit"),
        Entry(action: .status, language: .nl, phrase: "wat is dit nummer"),
        Entry(action: .status, language: .fr, phrase: "quel est ce morceau"),
        Entry(action: .status, language: .fr, phrase: "quelle chanson est ce"),
        Entry(action: .status, language: .de, phrase: "was lauft gerade"),
        Entry(action: .status, language: .de, phrase: "welches lied ist das"),
        Entry(action: .cancelSleep, language: .en, phrase: "cancel sleep timer"),
        Entry(action: .cancelSleep, language: .en, phrase: "stop the sleep timer"),
        Entry(action: .cancelSleep, language: .nl, phrase: "stop de slaaptimer"),
        Entry(action: .cancelSleep, language: .nl, phrase: "annuleer de slaaptimer"),
        Entry(action: .cancelSleep, language: .fr, phrase: "annule la minuterie"),
        Entry(action: .cancelSleep, language: .fr, phrase: "arrete la minuterie"),
        Entry(action: .cancelSleep, language: .de, phrase: "schlaftimer ausschalten"),
        Entry(action: .cancelSleep, language: .de, phrase: "schlaftimer abbrechen"),
    ]

    static func parse(_ text: String) -> Self? {
        guard text.count <= 200, text.range(of: "[0-9][.,][0-9]|[-−][0-9]", options: .regularExpression) == nil, !text.contains("\""), !text.contains("“") else { return nil }
        let value = normalize(text)
            .replacingOccurrences(of: "^(?:hey siri |hey echo |echo )", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^(?:please |alsjeblieft |bitte )", with: "", options: .regularExpression)
            .replacingOccurrences(of: " (?:please|alsjeblieft|aub|bitte|sil te plait)$", with: "", options: .regularExpression)
            .replacingOccurrences(of: " (?:in|on|with|op|met|via|dans|avec|sur|mit|bei) echo$", with: "", options: .regularExpression)
        guard !value.isEmpty else { return nil }
        if let match = entries.first(where: { $0.phrase == value }) {
            return Self(action: match.action, language: match.language)
        }
        let sleepPatterns: [(Language, String)] = [
            (.en, "^(?:sleep timer|stop in|sleep in) ([0-9]{1,3}) minutes?$"),
            (.nl, "^(?:slaaptimer|stop over) ([0-9]{1,3}) minuten?$"),
            (.fr, "^(?:minuterie|arrete dans) ([0-9]{1,3}) minutes?$"),
            (.de, "^(?:schlaftimer|stoppe in) ([0-9]{1,3}) minuten?$" )
        ]
        for (language, pattern) in sleepPatterns {
            if value.range(of: pattern, options: .regularExpression) != nil,
               let token = value.split(separator: " ").first(where: { Int($0) != nil }),
               let minutes = Int(token), (1...720).contains(minutes) {
                return Self(action: .sleep(minutes), language: language)
            }
        }
        // Same word count; at most one edit in one word of at least five letters.
        // Short switches (on/off, aan/uit) and all other words must match exactly.
        let matches = entries.filter { isSingleTypo(value, $0.phrase) }
        guard let match = matches.first,
              matches.allSatisfy({ $0.action == match.action }) else { return nil }
        return Self(action: match.action, language: match.language)
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "['’]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func isSingleTypo(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.split(separator: " "), b = rhs.split(separator: " ")
        guard a.count == b.count else { return false }
        let differences = zip(a, b).filter { $0 != $1 }
        guard differences.count == 1, let pair = differences.first,
              min(pair.0.count, pair.1.count) >= 5 else { return false }
        let x = Array(pair.0), y = Array(pair.1)
        guard abs(x.count - y.count) <= 1 else { return false }
        if x.count == y.count {
            let changed = x.indices.filter { x[$0] != y[$0] }
            if changed.count == 1 { return true }
            return changed.count == 2 && changed[1] == changed[0] + 1 &&
                x[changed[0]] == y[changed[1]] && x[changed[1]] == y[changed[0]]
        }
        let longer = x.count > y.count ? x : y, shorter = x.count > y.count ? y : x
        for index in longer.indices {
            var copy = longer; copy.remove(at: index)
            if copy == shorter { return true }
        }
        return false
    }
}
