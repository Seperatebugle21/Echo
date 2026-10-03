# Echo: audio, covers en equalizer

Uitgevoerd op Windows:
- 17 logische tests geslaagd, inclusief opslagmigratie, vier taalbundels en cropgrenzen.
- 139 Swift-bestanden zonder syntaxfouten. Dit is geen typecheck tegen het iOS SDK.
- 138 nieuwe vertaalkeys ten opzichte van Git, in Engels, Nederlands, Frans en Duits. Bestaande waarden behouden.
- Alle 48 covers gecontroleerd: 24 gradients/patronen met symbolen, 24 originele illustraties; ieder een JPEG van 512 × 512 pixels.
- Beide appmanifesten, voorbeeldaudio, bronpaden en diff-whitespacecontrole geslaagd.

Geïmplementeerd:
- Decoder en enginebediening op achtergrondqueues; voortgang via korte snapshots zonder worker.sync.
- Nieuwe seek- en nummeropdrachten vervangen oude opdrachten. Pauzestand blijft behouden bij zoeken.
- Playback wordt bevestigd bij renderprogressie; één herstelpoging bij stilstand, daarna een vertaalde fout met opnieuw proberen.
- Overgangsmodi, EQ, mono/stereo en previews behouden; luisteren wordt centraal geregistreerd, zonder view-level dubbele tellingen.
- Covergalerij en gedeelde crop-editor voor gewone/slimme playlists, optionele cover-ID’s en naamkeys, vertaalbare automatische namen, letterlijke handmatige namen en gedeelde aanmaakflow.
- Equalizer met curve, materialen, zes faders, presetkaarten en horizontale bediening bij grote toegankelijkheidstekst.

Nog niet uitgevoerd:
De iOS-build, native audiotests, UI-controles op simulator/iPad/iPhone, fysieke luistertests, native croporiëntatie/export en latency-metingen bij 100, 1.000 en 5.000 nummers. Windows kan dit niet bevestigen. Er wordt dus niet beweerd dat de P95-doelen al gehaald zijn of dat elk herstelscenario op toestel bewezen is.

EchoAudioEngineTests bevat native checks voor snelle wissels/zoeken, gepauzeerd zoeken, mixed sample rates, zeer korte en beschadigde bestanden, gapless-promotie, geïnjecteerde buffertekorten en engine-stilstand. FEATURES.md bevat Mac-commando’s en het native meetprotocol met weinig/veel luisterhistorie, alle overgangen, repeat, queuewijzigingen, previews, onderbrekingen, AirPlay, lockscreen, widgets en podcasts.

De gerichte ZIP bevat alle bestanden die verschillen van de eerder geleverde volledige performanceversie. De volledige ZIP bevat de hele bijgewerkte repository zonder .git. Er is niets naar GitHub gepusht.
