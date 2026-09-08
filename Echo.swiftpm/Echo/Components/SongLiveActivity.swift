import ActivityKit
import WidgetKit
import SwiftUI

struct SongLiveActivity: ActivityAttributes {
    
    public struct ContentState: Codable, Hashable {
        var isPlaying: Bool
    }
    
    
    var title: String
    var artist: String
}
