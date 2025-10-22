//
//  ImageManager.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 15/10/25.
//


import SwiftUI

@Observable
class ImageManager {
    let sourceImages: [String] = ["Kpop", "Rosalia", "Soccer_3", "Soccer_5", "Sports_4", "Sporty"]
    var savedImages: [UIImage] = []
    
    var selectedStickerIndex: Int? = nil
    
    func saveImage(_ image: UIImage) {
        savedImages.append(image)
    }
    
    func selectSticker(at index: Int) {
        guard index < savedImages.count else { return }
        selectedStickerIndex = index
    }
}
