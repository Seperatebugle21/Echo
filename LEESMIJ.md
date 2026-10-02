# Echo Widget: performanceherstel

Plaats de bestanden uit deze ZIP op dezelfde paden in je repository en commit naar Widget. SongLibraryPersistence.swift en SongMetadataUpdates.swift zijn nieuwe bestanden en moeten dus ook worden toegevoegd. De aangepaste project.yml neemt ze op in het testschema; de appbuild neemt ze automatisch op via Echo.swiftpm/Echo.

De ZIP bevat ook de vorige reparaties voor de twee archive-fouten. Start na het uploaden de GitHub Actions-build opnieuw en installeer de nieuwe IPA om de snelheid op je iPhone te controleren.

## Hersteld

- De metadatascan publiceerde meerdere wijzigingen per nummer. Elke wijziging encodeerde en schreef de hele bibliotheek inclusief covers op de hoofdthread. Nu worden maximaal 24 nummers per batch bijgewerkt en loopt opslag op een achtergrondqueue.
- Oude opslagopdrachten worden samengevoegd. Laden schrijft de bibliotheek niet direct terug. Bij het naar de achtergrond gaan krijgt de lopende opslag tijd om af te ronden.
- Slimme playlists berekenden dagelijkse luistervensters steeds opnieuw tijdens het sorteren. Nu gebeurt dat één keer per venster. Playlistresultaten en nummerindexen worden hergebruikt zolang hun invoer gelijk blijft.
- Metadata- en podcastcontroles houden de Fetch-initialisatie niet langer op.

14 logica-tests slagen. De Windows-benchmark met vijf evaluaties, 1.500 nummers en 90 dagen luistergegevens ging van ongeveer 5 seconden naar 0,06 seconde. De resultaten zijn identiek. Dit is geen meting van schermnavigatie op een iPhone. Native iOS-build en toestelsnelheid zijn hier nog niet geverifieerd.

Je bibliotheek hoeft niet gewist te worden. De bestaande opslagindeling blijft behouden.
