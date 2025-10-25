//
//  StickerPreviewView.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 22/10/25.
//

import SwiftUI
import RealityKit

struct StickerPreviewView: View {
    let image: UIImage
    @State private var debugInfo: String = "Generating texture..."
    
    var body: some View {
        VStack {
            Text("Sticker Preview")
                .font(.headline)
            
            // Preview de la imagen original
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 200)
                .border(Color.green, width: 2)
            
            // Info de debugging
            Text(debugInfo)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            
            Spacer()
        }
        .padding()
        .onAppear {
            testTextureCreation()
        }
    }
    
    private func testTextureCreation() {
        var info = "📊 Texture Creation Test:\n\n"
        
        info += "Image size: \(Int(image.size.width))x\(Int(image.size.height))\n"
        
        if let cgImage = image.cgImage {
            info += "✅ CGImage OK\n"
            
            if let _ = try? TextureResource(image: cgImage, options: .init(semantic: .color)) {
                info += "✅ TextureResource OK\n"
                info += "\n🎉 Ready for AR!"
            } else {
                info += "❌ TextureResource FAILED"
            }
        } else {
            info += "❌ CGImage FAILED"
        }
        
        debugInfo = info
    }
}
