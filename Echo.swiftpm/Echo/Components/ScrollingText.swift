import SwiftUI

struct ScrollingText: View {
    
    let text: String
    
    @State private var animate = false
    
    var body: some View {
        
        GeometryReader { geometry in
            
            let textWidth = text.widthOfString(
                usingFont: .systemFont(ofSize: 17)
            )
            
            if textWidth > geometry.size.width {
                
                HStack(spacing: 40) {
                    
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                    
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                }
                .offset(
                    x: animate ? -(textWidth + 40) : 0
                )
                .onAppear {
                    
                    withAnimation(
                        .linear(duration: Double(textWidth) / 25)
                        .repeatForever(autoreverses: false)
                    ) {
                        animate = true
                    }
                }
                
            } else {
                
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .clipped()
    }
}


extension String {
    
    func widthOfString(usingFont font: UIFont) -> CGFloat {
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        
        return self.size(withAttributes: attributes).width
    }
}
