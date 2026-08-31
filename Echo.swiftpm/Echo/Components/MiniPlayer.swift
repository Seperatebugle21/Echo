import SwiftUI
import UIKit


// MARK: - MiniPlayer

struct MiniPlayer: View {
    
    let onMinimize: () -> Void
    
    @Environment(AudioPlayerManager.self)
    private var audioPlayer
    
    @State private var showNowPlaying = false
    
    @State private var transitionDirection:
        AudioPlayerManager.PlaybackDirection = .next
    
    @State private var displayedSong: Song?
    
    @AppStorage("showCovers")
    private var showCovers = true
    
    
    var body: some View {
        
        Group {
            
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
                    
                    
                    // MARK: - AirPlay
                    
                    AirPlayButton()
                        .frame(
                            width: 30,
                            height: 30
                        )
                    
                    
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
                            
                            // Swipe down → MiniPlayer minimaliseren
                            
                            if value.translation.height > 50 {
                                
                                onMinimize()
                                
                                return
                            }
                            
                            
                            // Swipe up → Now Playing
                            
                            if value.translation.height < -50 {
                                
                                showNowPlaying = true
                                
                                return
                            }
                            
                            
                            // Swipe left → Next
                            
                            if value.translation.width < -50 {
                                
                                audioPlayer.next()
                                
                                return
                            }
                            
                            
                            // Swipe right → Previous
                            
                            if value.translation.width > 50 {
                                
                                audioPlayer.previous()
                            }
                        }
                )
            }
        }
        
        
        // MARK: - Custom Apple Music style presentation
        
        .background {
            
            NowPlayingUIKitPresenter(
                isPresented: $showNowPlaying
            ) {
                NowPlayingView()
            }
        }
    }
    
    
    // MARK: - Transition
    
    private var songTransition: AnyTransition {
        
        switch transitionDirection {
            
        case .next:
            
            return .asymmetric(
                insertion:
                    .move(edge: .trailing),
                removal:
                    .move(edge: .leading)
            )
            
            
        case .previous:
            
            return .asymmetric(
                insertion:
                    .move(edge: .leading),
                removal:
                    .move(edge: .trailing)
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
            
            
            // MARK: Title + artist
            
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


// MARK: - SwiftUI → UIKit Presenter

private struct NowPlayingUIKitPresenter<Content: View>:
    UIViewControllerRepresentable {
    
    @Binding var isPresented: Bool
    
    let content: () -> Content
    
    
    func makeCoordinator() -> Coordinator {
        
        Coordinator(
            isPresented: $isPresented
        )
    }
    
    
    func makeUIViewController(
        context: Context
    ) -> UIViewController {
        
        let controller = UIViewController()
        
        controller.view.backgroundColor = .clear
        
        return controller
    }
    
    
    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        
        context.coordinator.binding =
            $isPresented
        
        
        // MARK: Present
        
        if isPresented {
            
            guard
                context.coordinator.presentedController == nil,
                uiViewController.presentedViewController == nil
            else {
                return
            }
            
            
            let hostingController =
                UIHostingController(
                    rootView:
                        content()
                            .ignoresSafeArea()
                )
            
            
            hostingController.view.backgroundColor =
                .systemBackground
            
            
            let transitionDelegate =
                NowPlayingTransitionDelegate(
                    binding: $isPresented
                )
            
            
            hostingController.modalPresentationStyle =
                .custom
            
            hostingController.transitioningDelegate =
                transitionDelegate
            
            
            context.coordinator.transitionDelegate =
                transitionDelegate
            
            context.coordinator.presentedController =
                hostingController
            
            
            DispatchQueue.main.async {
                
                uiViewController.present(
                    hostingController,
                    animated: true
                )
            }
            
        }
        
        
        // MARK: Dismiss programmatically
        
        else {
            
            guard
                let presented =
                    context.coordinator.presentedController
            else {
                return
            }
            
            if presented.presentingViewController != nil {
                
                presented.dismiss(
                    animated: true
                )
            }
            
            context.coordinator.presentedController =
                nil
            
            context.coordinator.transitionDelegate =
                nil
        }
    }
    
    
    final class Coordinator {
        
        var binding: Binding<Bool>
        
        weak var presentedController:
            UIViewController?
        
        var transitionDelegate:
            NowPlayingTransitionDelegate?
        
        
        init(
            isPresented: Binding<Bool>
        ) {
            self.binding = isPresented
        }
    }
}


// MARK: - Transition Delegate

private final class NowPlayingTransitionDelegate:
    NSObject,
    UIViewControllerTransitioningDelegate {
    
    private var binding:
        Binding<Bool>
    
    private let interactionController =
        NowPlayingInteractiveDismissController()
    
    
    init(
        binding: Binding<Bool>
    ) {
        self.binding = binding
        
        super.init()
        
        
        interactionController.onDismissed = {
            [weak self] in
            
            self?.binding.wrappedValue = false
        }
    }
    
    
    func presentationController(
        forPresented presented:
            UIViewController,
        
        presenting:
            UIViewController?,
        
        source:
            UIViewController
    ) -> UIPresentationController? {
        
        let controller =
            NowPlayingPresentationController(
                presentedViewController:
                    presented,
                presenting:
                    presenting
            )
        
        interactionController
            .attach(
                to: presented
            )
        
        return controller
    }
    
    
    func animationController(
        forPresented presented:
            UIViewController,
        
        presenting:
            UIViewController,
        
        source:
            UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        
        NowPlayingPresentAnimator()
    }
    
    
    func animationController(
        forDismissed dismissed:
            UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        
        NowPlayingDismissAnimator()
    }
    
    
    func interactionControllerForDismissal(
        using animator:
            UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        
        interactionController
            .isInteracting
        ? interactionController
        : nil
    }
}


// MARK: - Presentation Controller

private final class NowPlayingPresentationController:
    UIPresentationController {
    
    
    override var frameOfPresentedViewInContainerView:
        CGRect {
        
        guard let containerView else {
            return .zero
        }
        
        return containerView.bounds
    }
    
    
    override func presentationTransitionWillBegin() {
        
        guard
            let containerView,
            let presentedView
        else {
            return
        }
        
        
        presentedView.frame =
            containerView.bounds
        
        
        presentedView.layer.cornerCurve =
            .continuous
        
        presentedView.layer.masksToBounds =
            true
        
        
        // Keep underlying app alive/visible
        
        presentingViewController
            .view
            .tintAdjustmentMode = .normal
    }
    
    
    override func containerViewWillLayoutSubviews() {
        
        super.containerViewWillLayoutSubviews()
        
        
        presentedView?.frame =
            frameOfPresentedViewInContainerView
    }
}


// MARK: - Present Animator

private final class NowPlayingPresentAnimator:
    NSObject,
    UIViewControllerAnimatedTransitioning {
    
    
    func transitionDuration(
        using transitionContext:
            UIViewControllerContextTransitioning?
    ) -> TimeInterval {
        
        0.48
    }
    
    
    func animateTransition(
        using transitionContext:
            UIViewControllerContextTransitioning
    ) {
        
        guard
            let toView =
                transitionContext.view(
                    forKey: .to
                )
        else {
            
            transitionContext
                .completeTransition(false)
            
            return
        }
        
        
        let container =
            transitionContext.containerView
        
        
        let finalFrame =
            transitionContext.finalFrame(
                for:
                    transitionContext
                        .viewController(
                            forKey: .to
                        )!
            )
        
        
        toView.frame = finalFrame
        
        
        // Start below screen
        
        toView.transform =
            CGAffineTransform(
                translationX: 0,
                y: finalFrame.height
            )
        
        
        toView.layer.cornerRadius = 28
        
        
        container.addSubview(toView)
        
        
        let animator =
            UIViewPropertyAnimator(
                duration:
                    transitionDuration(
                        using: transitionContext
                    ),
                dampingRatio: 0.88
            ) {
                
                toView.transform = .identity
                
                toView.layer.cornerRadius = 0
            }
        
        
        animator.addCompletion { position in
            
            transitionContext
                .completeTransition(
                    position == .end
                )
        }
        
        
        animator.startAnimation()
    }
}


// MARK: - Dismiss Animator

private final class NowPlayingDismissAnimator:
    NSObject,
    UIViewControllerAnimatedTransitioning {
    
    
    func transitionDuration(
        using transitionContext:
            UIViewControllerContextTransitioning?
    ) -> TimeInterval {
        
        0.42
    }
    
    
    func animateTransition(
        using transitionContext:
            UIViewControllerContextTransitioning
    ) {
        
        guard
            let fromView =
                transitionContext.view(
                    forKey: .from
                )
        else {
            
            transitionContext
                .completeTransition(false)
            
            return
        }
        
        
        let height =
            transitionContext
                .containerView
                .bounds
                .height
        
        
        let animator =
            UIViewPropertyAnimator(
                duration:
                    transitionDuration(
                        using: transitionContext
                    ),
                dampingRatio: 0.92
            ) {
                
                fromView.transform =
                    CGAffineTransform(
                        translationX: 0,
                        y: height
                    )
                
                fromView.layer.cornerRadius =
                    28
            }
        
        
        animator.addCompletion { _ in
            
            let cancelled =
                transitionContext
                    .transitionWasCancelled
            
            
            if cancelled {
                
                fromView.transform =
                    .identity
                
                fromView.layer.cornerRadius =
                    0
            }
            
            
            transitionContext
                .completeTransition(
                    !cancelled
                )
        }
        
        
        animator.startAnimation()
    }
}


// MARK: - Interactive Swipe Dismiss

private final class NowPlayingInteractiveDismissController:
    UIPercentDrivenInteractiveTransition {
    
    
    private weak var viewController:
        UIViewController?
    
    
    var isInteracting = false
    
    
    var onDismissed:
        (() -> Void)?
    
    
    private var shouldFinish =
        false
    
    
    func attach(
        to viewController:
            UIViewController
    ) {
        
        self.viewController =
            viewController
        
        
        let gesture =
            UIPanGestureRecognizer(
                target: self,
                action: #selector(
                    handlePan(_:)
                )
            )
        
        
        gesture.maximumNumberOfTouches =
            1
        
        
        viewController
            .view
            .addGestureRecognizer(
                gesture
            )
    }
    
    
    @objc
    private func handlePan(
        _ gesture:
            UIPanGestureRecognizer
    ) {
        
        guard
            let view =
                gesture.view,
            let viewController
        else {
            return
        }
        
        
        let translation =
            gesture.translation(
                in: view
            )
        
        
        let velocity =
            gesture.velocity(
                in: view
            )
        
        
        let height =
            max(
                view.bounds.height,
                1
            )
        
        
        // Only downward drag
        
        let progress =
            min(
                max(
                    translation.y / height,
                    0
                ),
                1
            )
        
        
        switch gesture.state {
            
            
        case .began:
            
            guard velocity.y > 0 else {
                return
            }
            
            
            isInteracting = true
            
            shouldFinish = false
            
            
            viewController.dismiss(
                animated: true
            )
            
            
        case .changed:
            
            guard isInteracting else {
                return
            }
            
            
            shouldFinish =
                progress > 0.22
                ||
                velocity.y > 1100
            
            
            update(progress)
            
            
            // Apple Music-ish corner radius
            
            let cornerProgress =
                min(
                    progress * 3,
                    1
                )
            
            
            view.layer.cornerRadius =
                28 * cornerProgress
            
            view.layer.cornerCurve =
                .continuous
            
            view.layer.masksToBounds =
                true
            
            
        case .ended:
            
            guard isInteracting else {
                return
            }
            
            
            isInteracting = false
            
            
            if shouldFinish {
                
                finish()
                
                DispatchQueue.main.async {
                    [weak self] in
                    
                    self?.onDismissed?()
                }
                
            } else {
                
                cancel()
                
                
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    usingSpringWithDamping: 0.88,
                    initialSpringVelocity: 0
                ) {
                    
                    view.layer.cornerRadius =
                        0
                }
            }
            
            
        case .cancelled,
             .failed:
            
            guard isInteracting else {
                return
            }
            
            
            isInteracting = false
            
            cancel()
            
            
            UIView.animate(
                withDuration: 0.25
            ) {
                
                view.layer.cornerRadius =
                    0
            }
            
            
        default:
            break
        }
    }
}
