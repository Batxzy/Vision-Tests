//
//  Arview.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 22/10/25.
//

import SwiftUI

struct ARModeView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(ImageManager.self) var imageManager
    @State private var showDebug = true
    
    var body: some View {
        ZStack {
            ARViewContainer()
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    // Botón de debug
                    Button {
                        showDebug.toggle()
                    } label: {
                        Image(systemName: showDebug ? "eye.fill" : "eye.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }
                .padding()
                
                if showDebug {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🐛 Debug Info")
                            .font(.headline)
                        
                        if let index = imageManager.selectedStickerIndex {
                            Text("Selected: Sticker #\(index)")
                            let img = imageManager.savedImages[index]
                            Text("Size: \(Int(img.size.width))x\(Int(img.size.height))")
                        } else {
                            Text("No sticker selected")
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding()
                }
                
                Spacer()
            }
        }
    }
}
