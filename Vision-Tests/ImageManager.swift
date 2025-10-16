//
//  ImageManager.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 15/10/25.
//


import SwiftUI

/// Manages the app's image data, including the source images and the user's saved creations.
@Observable
class ImageManager {
    /// The list of predefined image names. These must exist in your Asset Catalog.
    let sourceImages: [String] = ["Kpop", "Rosalia", "Soccer_3", "Soccer_5", "Sports_4", "Sporty"]
    
    /// The array that holds the filtered and saved images.
    var savedImages: [UIImage] = []
    
    /// Adds a UIImage to the saved images collection.
    func saveImage(_ image: UIImage) {
        savedImages.append(image)
    }
}
