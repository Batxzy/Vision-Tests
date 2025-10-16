//
//  ImageGalleryApp.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 15/10/25.
//


import SwiftUI

@main
struct ImageGalleryApp: App {
    /// The single source of truth for the app's data (source images, saved gallery).
    @State private var imageManager = ImageManager()
    
    /// The single instance of the image processing engine.
    @State private var effectsPipeline = EffectsPipeline()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(imageManager)
                .environment(effectsPipeline)
        }
    }
}