import SwiftUI
import AVKit

struct AirPlayButton: UIViewRepresentable {
    
    func makeUIView(context: Context) -> AVRoutePickerView {
        
        let view = AVRoutePickerView()
        
        view.tintColor = .label
        view.activeTintColor = .systemBlue
        
        return view
    }
    
    
    func updateUIView(
        _ uiView: AVRoutePickerView,
        context: Context
    ) {
        
    }
}
