
Claude finished the response
hoe kan je in swiftui een sheet openen zodat hij volledig het scherm bedekt tot boven maar niety een .fullscreen want ik wil dat je hem zo als een sheet kan wegswipen


Thought for 12s
Thought for 12s
In SwiftUI kun je met een gewone .sheet heel dicht bij een fullscreen-weergave komen door de detent op .large te zetten. Dat blijft een normale sheet (dus wegswipen werkt gewoon), in tegenstelling tot .fullScreenCover.

swift
struct ContentView: View {
    @State private var showSheet = false

    var body: some View {
        Button("Open") {
            showSheet = true
        }
        .sheet(isPresented: $showSheet) {
            DetailView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible) // optioneel: toon het greepje
        }
    }
}
Met .large als detent vult de sheet bijna het hele scherm, maar Apple laat bewust een klein randje bovenaan zichtbaar (als visuele hint dat het een sheet is die je kan wegswipen). Dat randje kun je met de standaard API niet weghalen zolang je een echte .sheet gebruikt.

Wil je dat randje toch helemaal weg (dus 100% tot boven, maar nog steeds swipe-to-dismiss), dan kan dat met een custom PresentationDetent:

swift
extension PresentationDetent {
    static let full = PresentationDetent.custom(FullDetent.self)
}

private struct FullDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        context.maxDetentValue
    }
}
En dan:

swift
.sheet(isPresented: $showSheet) {
    DetailView()
        .presentationDetents([.full])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(0) // optioneel: geen afgeronde hoeken
}
Dit forceert de sheet-hoogte naar de maximale waarde (context.maxDetentValue), waardoor hij helemaal tot boven komt, terwijl het onder water nog steeds een .sheet blijft — dus swipe-to-dismiss blijft gewoon werken, in tegenstelling tot .fullScreenCover waar je dat zelf zou moeten bouwen met een drag-gesture.

Kort samengevat:

Snel en simpel → .presentationDetents([.large]), met klein randje bovenaan.
Echt volledig scherm + swipeable → custom detent zoals hierboven.

import SwiftUI struct MiniPlayer: View { let onMinimize: () -> Void @Environment(AudioPlayerManager.self) private var audioPlayer @State private var showNowPlaying = false @State private var transitionDirection: AudioPlayerManager.PlaybackDirection = .next @

pasted

geef hiervoor het hele bestand:


Thought for 4s
Thought for 4s
Hier is het volledige bestand met de sheet aangepast zodat hij volledig tot boven het scherm bedekt (via een custom PresentationDetent), maar gewoon een .sheet blijft — dus wegswipen blijft werken:

swift
import SwiftUI


// MARK: - Custom Full Detent

extension PresentationDetent {
    static let full = PresentationDetent.custom(FullDetent.self)
}

private struct FullDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        context.maxDetentValue
    }
}


struct MiniPlayer: View {
    let onMinimize: () -> Void
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showNowPlaying = false
    @State private var transitionDirection: AudioPlayerManager.PlaybackDirection = .next
    @State private var displayedSong: Song?
    
    @AppStorage("showCovers") private var showCovers = true
    
    
    
    
    
    var body: some View {
        
        if let song = audioPlayer.currentSong {
            
            HStack(spacing: 10) {
                
                // MARK: - Animated song
                
                ZStack {
                    
                    if let displayedSong {
                        
                        songContent(displayedSong)
                            .id(displayedSong.id)
                            .transition(
                                songTransition
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .clipped()


                AirPlayButton()
                .frame(width: 30, height: 30)
                
                
                // MARK: - Play / Pause
                
                Button {
                    audioPlayer.togglePlayPause()
                    
                } label: {
                    
                    Image(
                        systemName:
                            audioPlayer.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                    )
                    .font(.title2)
                    .frame(
                        width: 40,
                        height: 40
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            
            
            // MARK: - Liquid Glass
            
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            
            .overlay {
                
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    .white.opacity(0.12),
                    lineWidth: 0.7
                )
            }
            
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            
            .shadow(
                radius: 12,
                y: 5
            )
            
            .padding(.horizontal)
            
            
            // MARK: - Song changed
            
            .onChange(of: song.id) {
                
                transitionDirection =
                audioPlayer.lastPlaybackDirection
                
                withAnimation(
                    .spring(
                        response: 0.36,
                        dampingFraction: 0.88
                    )
                ) {
                    displayedSong = song
                }
            }
            
        
            
            // MARK: - Initial song
            
            .onAppear {
                
                if displayedSong == nil {
                    displayedSong = song
                }
            }
            
            
            // MARK: - Open Now Playing
            
            .onTapGesture {
                showNowPlaying = true
            }
            
            
            // MARK: - Swipe
            
            .gesture(
                DragGesture()
                    .onEnded { value in
                        
                        // Naar beneden → MiniPlayer minimaliseren
                        if value.translation.height > 50 {
                            
                            onMinimize()
                            
                            return
                        }

                        if value.translation.height < -50 {
                            
                            showNowPlaying = true
                            
                            return
                        }
                        
                        
                        // Naar links → volgend nummer
                        if value.translation.width < -50 {
                            
                            audioPlayer.next()
                            
                            return
                        }
                        
                        
                        // Naar rechts → vorig nummer
                        if value.translation.width > 50 {
                            
                            audioPlayer.previous()
                        }
                    }
            )
            
            
            // MARK: - Now Playing
            
            .sheet(
                isPresented: $showNowPlaying
            ) {
                NowPlayingView()
                    .presentationDetents([.full])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(0)
            }
        }
    }
    
    
    // MARK: - Transition
    
    private var songTransition: AnyTransition {
        
        switch transitionDirection {
            
        case .next:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
            
        case .previous:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
            
        case .fade:
            return .opacity
        }
    }
    
    
    // MARK: - Song Content
    
    @ViewBuilder
    private func songContent(
        _ song: Song
    ) -> some View {
        
        HStack(spacing: 10) {
            
            // MARK: Cover
            
            Group {
                
                if showCovers,
                   let data = song.coverData,
                   let image = UIImage(data: data) {
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                    
                } else {
                    
                    Image(
                        systemName: "music.note"
                    )
                    .font(.title2)
                    .frame(
                        width: 45,
                        height: 45
                    )
                    .background(
                        .thinMaterial
                    )
                }
            }
            .frame(
                width: 45,
                height: 45
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            
            
            // MARK: Titel + artiest
            
            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                
                ScrollingText(
                    text: song.title
                )
                .frame(
                    height: 22
                )
                
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }
}
Wat er is toegevoegd/veranderd:

De FullDetent-struct en PresentationDetent.full-extensie bovenaan het bestand.
Op NowPlayingView() binnen de .sheet heb ik .presentationDetents([.full]), .presentationDragIndicator(.visible) en .presentationCornerRadius(0) toegevoegd, zodat de sheet helemaal tot boven komt maar nog steeds wegswipebaar blijft.
Wil je liever nog het kleine randje/greepje bovenaan behouden (de standaard Apple-look met .large), dan laat je gewoon .presentationDetents([.large]) staan in plaats van .full.

de sheet laat nog een klein beetje plaats over


Thought for 5s
Thought for 5s
Klopt — dat is helaas geen bug maar bewust gedrag van iOS. Zelfs met een custom PresentationDetent die context.maxDetentValue teruggeeft, laat het systeem altijd een klein randje (~5-10pt) bovenaan vrij bij een .sheet. Dat is intentioneel zodat de gebruiker altijd kan zien/voelen dat het om een sheet gaat (en niet een .fullScreenCover). Er is geen publieke API om dat weg te halen zolang je een echte .sheet gebruikt.

Je hebt dus twee opties:

Optie 1 — Accepteren
Het randje is klein en de meeste apps (ook Apple's eigen apps, zoals Muziek of Maps) laten dit gewoon zo staan. Dit is de "gewone" manier en waarschijnlijk de beste keuze.

Optie 2 — Zelf bouwen met .fullScreenCover + eigen swipe-to-dismiss
Als je echt 100% tot de bovenrand wil zónder enig randje, moet je een .fullScreenCover gebruiken en zelf een drag-gesture bouwen die het venster laat meebewegen en sluit bij voldoende swipe naar beneden — zodat het zich gedraagt als een sheet.

Voorbeeld:

swift
.fullScreenCover(isPresented: $showNowPlaying) {
    NowPlayingView()
        .interactiveDismiss(isPresented: $showNowPlaying)
}
swift
struct InteractiveDismiss: ViewModifier {
    @Binding var isPresented: Bool
    @State private var offset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .offset(y: max(offset, 0))
            .background(.black.opacity(1 - min(offset / 400, 0.4)))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            offset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            dismiss()
                        } else {
                            withAnimation(.spring()) {
                                offset = 0
                            }
                        }
                    }
            )
            .animation(.interactiveSpring(), value: offset)
    }
}

extension View {
    func interactiveDismiss(isPresented: Binding<Bool>) -> some View {
        self.modifier(InteractiveDismiss(isPresented: isPresented))
    }
}
Dit geeft je volledige controle: geen randje bovenaan, en toch een swipe-down-to-dismiss gevoel zoals een sheet. Het kost wel wat extra werk (bv. drag-indicator zelf tekenen, corner radius animeren tijdens het slepen, etc.) om het er precies zo uit te laten zien als een systeem-sheet.

Advies: tenzij het echt cruciaal is voor je design, zou ik optie 1 aanraden — het randje is subtiel en je krijgt alle systeemgedrag (physics, drag-indicator, corner radius animatie) gratis mee.

Welke richting wil je op?


Thought for 12s
Thought for 12s
Ah juist — dat komt door de .background(.black.opacity(1 - min(offset / 400, 0.4))) die ik toevoegde op de content zelf. Naarmate je sleept (offset stijgt), wordt die achtergrond steeds transparanter, en dan schijnt de onderliggende systeemlaag van de .fullScreenCover erdoorheen — en die is blijkbaar grijs in plaats van zwart.

De fix: zet een aparte, volledig ondoorzichtige zwarte laag achter de content in een ZStack, in plaats van transparantie op de content zelf toe te passen. Zo wordt het gat dat ontstaat door de offset altijd opgevuld met zwart, nooit met de systeemgrijze laag erachter.

swift
struct InteractiveDismiss: ViewModifier {
    @Binding var isPresented: Bool
    @State private var offset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        ZStack {
            
            // Altijd ondoorzichtig zwart, vult het hele scherm
            Color.black
                .ignoresSafeArea()
            
            content
                .offset(y: max(offset, 0))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: offset > 0 ? 40 : 0,
                        style: .continuous
                    )
                )
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        offset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring()) {
                            offset = 0
                        }
                    }
                }
        )
        .animation(.interactiveSpring(), value: offset)
    }
}
Belangrijkste verschil:

Geen .opacity() meer op de achtergrond — die zorgde net voor de doorschijnende grijze flits.
Color.black.ignoresSafeArea() zit nu vast achter de content in de ZStack, dus wat je ook doet met de offset, het gat bovenaan toont altijd zwart.
MiniPlayer.swift zelf hoeft niet te veranderen, deze blijft:

swift
.fullScreenCover(isPresented: $showNowPlaying) {
    NowPlayingView()
        .interactiveDismiss(isPresented: $showNowPlaying)
}
Test opnieuw — dit zou het grijze randje volledig moeten wegnemen tijdens het slepen.


import SwiftUI // MARK: - Custom Full Detent extension PresentationDetent { static let full = PresentationDetent.custom(FullDetent.self) } private struct FullDetent: CustomPresentationDetent { static func height(in context: Context) -> CGFloat? { context.maxDetentValue

pasted

zo is goed maar nu als ik aan het swipen ben naar beneden toont het nu gewoon wit maar ik wil dat het de view die eracher zit toont dus stel dat songsview er was voor alleer daty ik nowplayin gopende wil ik dat ik de view al kan zien als ik naar beneden swipe zoals een sheet maar nu is het gewoon wit. precies hetzelfde als apple music dus het is mogelijk


Thought for 1m 1s
Thought for 1m 1s
Ah, dat is een gekend "probleem" met .fullScreenCover: zodra hij gepresenteerd wordt, verwijdert iOS de onderliggende view volledig uit de renderboom (voor performance), en toont een systeem-achtergrond (wit/zwart) op de plekken waar je content niet zichtbaar is. Dat is dus niet op te lossen met enkel .background() of .opacity() — de standaard .fullScreenCover staat het gewoon niet toe.

Apple Music (en jij dus ook) kan dit omdat ze geen standaard .fullScreenCover gebruiken, maar een custom modal presentatie waarbij de onderliggende view expliciet "in leven" blijft (.overFullScreen in plaats van .fullScreen) met een transparante achtergrond. Dat kan alleen via een UIViewControllerRepresentable-trucje, aangezien SwiftUI dit zelf niet blootstelt.

Hier is het volledige bestand met die aanpak:

swift
import SwiftUI
import UIKit


// MARK: - Custom Full Detent

extension PresentationDetent {
    static let full = PresentationDetent.custom(FullDetent.self)
}

private struct FullDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        context.maxDetentValue
    }
}


// MARK: - Transparent Full Screen Cover

extension View {
    func transparentFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        
        self.background(
            TransparentFullScreenCoverHelper(
                isPresented: isPresented,
                fullScreenContent: content
            )
        )
    }
}

private struct TransparentFullScreenCoverHelper<Content: View>: UIViewControllerRepresentable {
    
    @Binding var isPresented: Bool
    let fullScreenContent: () -> Content
    
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    
    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        
        if isPresented {
            
            guard uiViewController.presentedViewController == nil else { return }
            
            let hostingController = UIHostingController(
                rootView: fullScreenContent()
            )
            
            hostingController.view.backgroundColor = .clear
            hostingController.view.isOpaque = false
            hostingController.modalPresentationStyle = .overFullScreen
            
            uiViewController.present(
                hostingController,
                animated: true
            )
            
        } else {
            
            guard uiViewController.presentedViewController != nil else { return }
            
            uiViewController.dismiss(animated: false)
        }
    }
}


struct MiniPlayer: View {
    let onMinimize: () -> Void
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showNowPlaying = false
    @State private var transitionDirection: AudioPlayerManager.PlaybackDirection = .next
    @State private var displayedSong: Song?
    
    @AppStorage("showCovers") private var showCovers = true
    
    
    
    
    
    var body: some View {
        
        if let song = audioPlayer.currentSong {
            
            HStack(spacing: 10) {
                
                // MARK: - Animated song
                
                ZStack {
                    
                    if let displayedSong {
                        
                        songContent(displayedSong)
                            .id(displayedSong.id)
                            .transition(
                                songTransition
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .clipped()


                AirPlayButton()
                .frame(width: 30, height: 30)
                
                
                // MARK: - Play / Pause
                
                Button {
                    audioPlayer.togglePlayPause()
                    
                } label: {
                    
                    Image(
                        systemName:
                            audioPlayer.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                    )
                    .font(.title2)
                    .frame(
                        width: 40,
                        height: 40
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            
            
            // MARK: - Liquid Glass
            
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            
            .overlay {
                
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    .white.opacity(0.12),
                    lineWidth: 0.7
                )
            }
            
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            
            .shadow(
                radius: 12,
                y: 5
            )
            
            .padding(.horizontal)
            
            
            // MARK: - Song changed
            
            .onChange(of: song.id) {
                
                transitionDirection =
                audioPlayer.lastPlaybackDirection
                
                withAnimation(
                    .spring(
                        response: 0.36,
                        dampingFraction: 0.88
                    )
                ) {
                    displayedSong = song
                }
            }
            
        
            
            // MARK: - Initial song
            
            .onAppear {
                
                if displayedSong == nil {
                    displayedSong = song
                }
            }
            
            
            // MARK: - Open Now Playing
            
            .onTapGesture {
                showNowPlaying = true
            }
            
            
            // MARK: - Swipe
            
            .gesture(
                DragGesture()
                    .onEnded { value in
                        
                        // Naar beneden → MiniPlayer minimaliseren
                        if value.translation.height > 50 {
                            
                            onMinimize()
                            
                            return
                        }

                        if value.translation.height < -50 {
                            
                            showNowPlaying = true
                            
                            return
                        }
                        
                        
                        // Naar links → volgend nummer
                        if value.translation.width < -50 {
                            
                            audioPlayer.next()
                            
                            return
                        }
                        
                        
                        // Naar rechts → vorig nummer
                        if value.translation.width > 50 {
                            
                            audioPlayer.previous()
                        }
                    }
            )
            
            
            // MARK: - Now Playing
            
            .transparentFullScreenCover(isPresented: $showNowPlaying) {
                NowPlayingView()
                    .interactiveDismiss(isPresented: $showNowPlaying)
            }
        }
    }
    
    
    // MARK: - Transition
    
    private var songTransition: AnyTransition {
        
        switch transitionDirection {
            
        case .next:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
            
        case .previous:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
            
        case .fade:
            return .opacity
        }
    }
    
    
    // MARK: - Song Content
    
    @ViewBuilder
    private func songContent(
        _ song: Song
    ) -> some View {
        
        HStack(spacing: 10) {
            
            // MARK: Cover
            
            Group {
                
                if showCovers,
                   let data = song.coverData,
                   let image = UIImage(data: data) {
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                    
                } else {
                    
                    Image(
                        systemName: "music.note"
                    )
                    .font(.title2)
                    .frame(
                        width: 45,
                        height: 45
                    )
                    .background(
                        .thinMaterial
                    )
                }
            }
            .frame(
                width: 45,
                height: 45
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            
            
            // MARK: Titel + artiest
            
            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                
                ScrollingText(
                    text: song.title
                )
                .frame(
                    height: 22
                )
                
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }
}


// MARK: - Interactive Dismiss

struct InteractiveDismiss: ViewModifier {
    @Binding var isPresented: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: max(offset, 0))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: offset > 0 ? 40 : 0,
                    style: .continuous
                )
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            offset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        
                        if value.translation.height > 120 {
                            
                            withAnimation(
                                .easeInOut(duration: 0.25)
                            ) {
                                offset = UIScreen.main.bounds.height
                            }
                            
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + 0.25
                            ) {
                                isPresented = false
                                offset = 0
                            }
                            
                        } else {
                            
                            withAnimation(.spring()) {
                                offset = 0
                            }
                        }
                    }
            )
            .animation(.interactiveSpring(), value: offset)
    }
}

extension View {
    func interactiveDismiss(isPresented: Binding<Bool>) -> some View {
        self.modifier(InteractiveDismiss(isPresented: isPresented))
    }
}
Wat er is veranderd
TransparentFullScreenCoverHelper (nieuw): een UIViewControllerRepresentable die de NowPlayingView presenteert met modalPresentationStyle = .overFullScreen in plaats van het standaard .fullScreen. Dat is het cruciale verschil — .overFullScreen houdt de onderliggende view in de hiërarchie "levend", en met backgroundColor = .clear op de hostingController schijnt die onderliggende view (je MiniPlayer/SongsView) er gewoon doorheen op elke plek waar NowPlayingView niet volledig dekkend is (dus tijdens het slepen).
.transparentFullScreenCover(isPresented:) vervangt nu .fullScreenCover(isPresented:) in MiniPlayer.
InteractiveDismiss gebruikt niet langer @Environment(\.dismiss), maar zet de isPresented-binding rechtstreeks op false — nodig omdat we nu zelf de presentatie beheren via UIKit, dus de automatische SwiftUI-dismiss-koppeling bestaat niet meer. Bij het loslaten na voldoende swipe wordt eerst de view zelf naar onder geanimeerd, en pas daarna (na 0.25s) de binding op false gezet + dismiss (animated: false) aangeroepen, zodat er geen dubbele/conflicterende animatie ontstaat.
Test dit even goed uit — als de content van NowPlayingView zelf nog ergens een niet-transparante achtergrond mist (bv. bij een venster zonder cover), zorg dan dat de else { Color.black }-fallback in nowPlayingBackground blijft staan, zodat de view zelf er nog steeds correct uitziet wanneer hij niet aan het slepen is.



You are out of free messages until 3:00 PM
Write a message…


Claude is AI and can make mistakes. Please double-check responses.
Pasted content
7.86 KB •294 lines
•
Formatting may be inconsistent from source
import SwiftUI


struct MiniPlayer: View {
    let onMinimize: () -> Void
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showNowPlaying = false
    @State private var transitionDirection: AudioPlayerManager.PlaybackDirection = .next
    @State private var displayedSong: Song?
    
    @AppStorage("showCovers") private var showCovers = true
    
    
    
    
    
    var body: some View {
        
        if let song = audioPlayer.currentSong {
            
            HStack(spacing: 10) {
                
                // MARK: - Animated song
                
                ZStack {
                    
                    if let displayedSong {
                        
                        songContent(displayedSong)
                            .id(displayedSong.id)
                            .transition(
                                songTransition
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .clipped()


                AirPlayButton()
                .frame(width: 30, height: 30)
                
                
                // MARK: - Play / Pause
                
                Button {
                    audioPlayer.togglePlayPause()
                    
                } label: {
                    
                    Image(
                        systemName:
                            audioPlayer.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                    )
                    .font(.title2)
                    .frame(
                        width: 40,
                        height: 40
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            
            
            // MARK: - Liquid Glass
            
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            
            .overlay {
                
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    .white.opacity(0.12),
                    lineWidth: 0.7
                )
            }
            
