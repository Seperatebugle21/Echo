import SwiftUI
import AVKit

struct AirPlayButton: UIViewRepresentable {
    
    var tintColor: UIColor = .label
    var activeTintColor: UIColor = .systemBlue
    
    
    func makeUIView(
        context: Context
    ) -> AVRoutePickerView {
        
        let view = AVRoutePickerView()
        
        view.tintColor = tintColor
        view.activeTintColor = activeTintColor
        
        return view
    }
    
    
    func updateUIView(
        _ uiView: AVRoutePickerView,
        context: Context
    ) {
        
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}
