
// THIS VIEW ONLY PURPOSE WAS TO TEST WICH SDK THE APP USES 
//THIS VIEW IS NOT CONNECTED ALONE TO THE APP

// YOU ARE FREE TO DELETE THIS VIEW WITHOUT CHANGING THE APP ITSELF





import SwiftUI

struct SongRow: View {
    var body: some View {
        Text("Test")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        print("test")
                    } label: {
                        Image(systemName: "waveform")
                    }
                }
            }
    }
}
