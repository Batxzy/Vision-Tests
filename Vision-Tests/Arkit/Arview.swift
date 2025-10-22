//
//  Arview.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 22/10/25.
//

import SwiftUI

struct Arview: View {
    @Environment(\.imageManager) var imageManager
    
    var body: some View {
        ARViewContainer(imageManager: Environment<ImageManager>)
    }
}

#Preview {
    Arview()
}
