# Siri and short audio commands

Echo provides localized App Shortcut phrases, action titles, entity labels and errors in English, Dutch, French, German, Spanish, Italian, Portuguese, Polish, Turkish, Japanese, Korean and Simplified Chinese. These use system localization rather than Echo's in-app `selectedLanguage`. Siri itself does not offer every one of these languages (Polish, for example); there the phrases are available in Shortcuts but not by voice. Siri's speech-recognition language and app routing are controlled by iOS: Echo cannot enable unrestricted multilingual Siri recognition or intercept commands that Siri sends elsewhere.

The ten automatically discoverable shortcuts cover songs, playlists, favorite playback, shuffle on/off, repeat one/all/off, Flow and favoriting the current song. Example registered phrases are “Start flow in Echo”, “Shuffle this song in Echo” and “Favorite this song in Echo”, with localized equivalents. Flow uses the playing song when available. Favoriting is idempotent: repeating the request never unfavorites a song.

Additional actions in Apple Shortcuts include removing a favorite, stopping Flow, pause/resume, next/previous, playback status, setting/cancelling the sleep timer and **Echo command**. They reuse the current library and playback manager; no AI provider or network call is needed to interpret a short command.

## Short names without saying Echo

Apple requires the application-name token in registered App Shortcut phrases. To invoke an exact short phrase without the app name, create a personal shortcut in Apple Shortcuts, add the relevant Echo action, and name it for example **Start de flow**, **Herhaal dit liedje**, **Start flow**, **Lance le flow** or **Starte Flow**. Siri can invoke that personal shortcut by its name; system recognition still applies.

For variable commands, create a personal shortcut containing **Echo command**, set its Command field to **Ask Each Time**, and invoke that shortcut. Dictated or typed text reaching this action is parsed against all twelve languages, independently of Echo's interface language. Japanese, Korean and Chinese commands may omit spaces and may put the app name first (“Echoで次の曲”, “在Echo里随机播放”); typo tolerance applies only to alphabetic scripts, because one character can flip such a command. Examples:

| English | Nederlands | Français | Deutsch |
| --- | --- | --- | --- |
| start flow from this song | start de flow uit dit liedje | lance le flow avec ce morceau | starte Flow mit diesem Lied |
| favorite this song | maak dit liedje favoriet | ajoute ce morceau aux favoris | markiere dieses Lied als Favorit |
| repeat this song | herhaal dit liedje | répète ce morceau | wiederhole dieses Lied |
| sleep timer 30 minutes | slaaptimer 30 minuten | minuterie 30 minutes | Schlaftimer 30 Minuten |

| Español | Italiano | Português | Polski |
| --- | --- | --- | --- |
| repite esta canción | ripeti questa canzone | repete esta música | powtarzaj ten utwór |
| temporizador 30 minutos | timer 30 minuti | temporizador 30 minutos | wyłącznik czasowy 30 minut |

| Türkçe | 日本語 | 한국어 | 简体中文 |
| --- | --- | --- | --- |
| bu şarkıyı tekrarla | この曲をリピート | 이 노래 반복 | 单曲循环 |
| 30 dakika sonra durdur | スリープタイマー30分 | 취침 타이머 30분 | 30分钟后停止 |

The command action tolerates one insertion, deletion, substitution or adjacent transposition in a word of at least five characters (for example “shuffel dit liedje”). It does not change short on/off words, drop negation, interpret multiple actions, or guess named-song commands. Unrecognized input fails without changing playback. Actual song and playlist entity searches retain the existing fuzzy matching; title words such as “Play” and “Start” are no longer stripped out of entity queries.

## Validation

Eight portable XCTest cases pass for all four languages, current-song commands, typo handling, opposite states, refusal of negation/compound/unknown commands, sleep-timer bounds, and independence from the app-language preference. Siri metadata keys and every localized shortcut parameter token were checked, and changed Swift files pass syntax parsing. No native build or Siri/device verification was run or monitored for this change, as requested. On-device verification is needed for Siri recognition, Shortcuts parameter prompting, background playback and localized App Shortcut registration.
