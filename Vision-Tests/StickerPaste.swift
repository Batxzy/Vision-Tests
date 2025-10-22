//
//  StickerPaste.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 22/10/25.
//

import SwiftUI

struct StickerPickerView: View {
    @Environment(ImageManager.self) var imageManager
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                ForEach(imageManager.savedImages.indices, id: \.self) { index in
                    Image(uiImage: imageManager.savedImages[index])
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .onTapGesture {
                            imageManager.selectSticker(at: index)
                        }
                }
            }
        }
    }
}


#Preview {
    StickerPickerView()
}
