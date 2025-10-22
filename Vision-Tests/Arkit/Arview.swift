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
    
    var body: some View {
        ZStack {
            ARViewContainer()
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
