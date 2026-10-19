import Foundation
import XCTest

final class EchoSpokenCommandTests: XCTestCase {
    func testFlowInAllFourLanguages() {
        let samples: [(String, EchoSpokenCommand.Language)] = [
            ("start the flow", .en), ("start de flow", .nl),
            ("démarre le flow", .fr), ("starte den flow", .de)
        ]
        for (text, language) in samples {
            XCTAssertEqual(EchoSpokenCommand.parse(text)?.action, .flow, text)
            XCTAssertEqual(EchoSpokenCommand.parse(text)?.language, language, text)
        }
    }
    func testCurrentSongAndOptionalAppName() {
        for text in ["start de flow uit dit liedje", "start flow from this song in Echo",
                     "lance le flow avec ce morceau", "starte flow mit diesem Lied"] {
            XCTAssertEqual(EchoSpokenCommand.parse(text)?.action, .flowCurrent, text)
        }
        XCTAssertEqual(EchoSpokenCommand.parse("Shuffle dit liedje op Echo")?.action, .shuffleOn)
        XCTAssertEqual(EchoSpokenCommand.parse("Herhaal dit liedje")?.action, .repeatOne)
    }
    func testTypoAndTranspositionTolerance() {
        XCTAssertEqual(EchoSpokenCommand.parse("shuffel dit liedje")?.action, .shuffleOn)
        XCTAssertEqual(EchoSpokenCommand.parse("herhaal dit liedj")?.action, .repeatOne)
        XCTAssertEqual(EchoSpokenCommand.parse("favortie this song")?.action, .favorite)
        XCTAssertEqual(EchoSpokenCommand.parse("repete ce morceua")?.action, .repeatOne)
        XCTAssertEqual(EchoSpokenCommand.parse("wiederhole dieses Leid")?.action, nil) // Short words are not guessed.
    }
    func testFavoritesInAllLanguages() {
        for text in ["favorite this song", "maak dit liedje favoriet", "ajoute ce morceau aux favoris",
                     "markiere dieses Lied als Favorit"] {
            XCTAssertEqual(EchoSpokenCommand.parse(text)?.action, .favorite, text)
        }
        for text in ["remove this song from favorites", "haal dit nummer uit favorieten",
                     "retire ce morceau des favoris", "entferne dieses Lied aus den Favoriten"] {
            XCTAssertEqual(EchoSpokenCommand.parse(text)?.action, .unfavorite, text)
        }
    }
    func testNegationsUnknownTitlesAndMultipleCommandsAreNotGuessed() {
        for text in ["do not favorite this song", "maak dit liedje niet favoriet", "ne repete pas ce morceau",
                     "wiederhole dieses Lied nicht", "favorite Yesterday", "shuffle on and repeat all",
                     "start flow and delete my library", "repeat this song tomorrow", "turn shuffle of",
                     "\"repeat this song\"", "", String(repeating: "a", count: 201)] {
            XCTAssertNil(EchoSpokenCommand.parse(text), text)
        }
    }
    func testOppositeStatesStayDistinct() {
        XCTAssertEqual(EchoSpokenCommand.parse("turn shuffle off")?.action, .shuffleOff)
        XCTAssertEqual(EchoSpokenCommand.parse("zet shuffle aan")?.action, .shuffleOn)
        XCTAssertEqual(EchoSpokenCommand.parse("zet shuffle uit")?.action, .shuffleOff)
        XCTAssertEqual(EchoSpokenCommand.parse("désactive le mode aléatoire")?.action, .shuffleOff)
        XCTAssertEqual(EchoSpokenCommand.parse("wiederholung ausschalten")?.action, .repeatOff)
    }
    func testSleepTimerBoundsInAllLanguages() {
        for text in ["sleep timer 30 minutes", "slaaptimer 30 minuten", "minuterie 30 minutes", "schlaftimer 30 minuten"] {
            XCTAssertEqual(EchoSpokenCommand.parse(text)?.action, .sleep(30), text)
        }
        XCTAssertNil(EchoSpokenCommand.parse("sleep timer 0 minutes"))
        XCTAssertNil(EchoSpokenCommand.parse("sleep timer 721 minutes"))
        XCTAssertNil(EchoSpokenCommand.parse("sleep timer -5 minutes"))
        XCTAssertNil(EchoSpokenCommand.parse("sleep timer 1.5 minutes"))
    }
    func testLanguageDoesNotDependOnAppPreference() {
        let key = "selectedLanguage", previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set("nl", forKey: key)
        XCTAssertEqual(EchoSpokenCommand.parse("favorite this song")?.language, .en)
        XCTAssertEqual(EchoSpokenCommand.parse("répète ce morceau")?.language, .fr)
        XCTAssertEqual(EchoSpokenCommand.parse("nächster Titel")?.language, .de)
    }
}
