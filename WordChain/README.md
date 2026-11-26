# Schakel

A daily word-bridge game for iPhone and iPad, written in SwiftUI. You can play it in Dutch or English.

Each round gives you clue words. Find the word that forms a real compound word or common phrase with them:

| Round | Example (EN) | Example (NL) |
| --- | --- | --- |
| Two-word bridge | SUN ▢ POT → **flower** | ZON ▢ POT → **bloem** |
| Three-word bridge | FOOT, HAND, ▢ GAME → **ball** | VOET, HAND, ▢ SPEL → **bal** |
| Long bridge | BOOK ▢ ▢ ROOM → **case, study** | VOET ▢ ▢ JAS → **bad, kamer** |

- **Daily puzzle**: 5 rounds (3 two-word bridges, 1 three-word bridge, 1 long bridge), the same for everyone on a given day. One guess per word, up to 1000 points per round, 5000 a day. Each letter you ask for costs points. Another word that fits all clues counts too.
- **Endless**: a new round after every answer, with no end. You have 3 lives and each miss costs one. Your best run is kept.
- **Archive**: every earlier day can be played. Archive games don't count toward the streak.
- Statistics per language: streak, average, best day and score distribution. There is also a share text with coloured squares.

## Words

Rounds are generated from the link lists in `Resources/pairs_en.txt` and `Resources/pairs_nl.txt`. Each line is `first second`, and `= written form` gives the spelling when it isn't simply the two words glued together (`boek kast = boekenkast`). Daily rounds use a fixed seed per day and language, so everyone gets the same puzzle. Endless rounds avoid the last 2000 rounds you played.

To add words, append lines and run:

```
python3 Scripts/check_words.py
```

It checks the format and duplicates, and reports how many chains the lists allow.

## Building

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```
brew install xcodegen
cd WordChain && xcodegen generate
open Schakel.xcodeproj
```

The workflow `.github/workflows/Schakel.yml` builds the app and runs the unit tests on a simulator for every push that touches `WordChain/`. It uploads an unsigned `Schakel.ipa` as an artifact. Requires iOS 17.
