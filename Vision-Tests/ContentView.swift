import SwiftUI

// MARK: - Main Content View (with TabView)
struct ContentView: View {
    var body: some View {
        TabView {
            FiltersView()
                .tabItem { Label("Filters", systemImage: "photo.on.rectangle.angled") }
            
            SavedImagesView()
                .tabItem { Label("Saved", systemImage: "bookmark.fill") }
        }
    }
}


// MARK: - Filters Tab
struct FiltersView: View {
    @Environment(ImageManager.self) private var imageManager
    @Environment(EffectsPipeline.self) private var pipeline
    @State private var isShowingFilterSheet = false
    
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(imageManager.sourceImages, id: \.self) { imageName in
                        Button(action: {
                            if let image = UIImage(named: imageName) {
                                pipeline.inputImage = image
                                Task {
                                    await pipeline.processImage()
                                    isShowingFilterSheet = true
                                }
                            }
                        }) {
                            Image(imageName)
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                .aspectRatio(1, contentMode: .fit).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1), lineWidth: 2))
                        }
                    }
                }.padding()
            }
            .navigationTitle("Select an Image")
        }
        .sheet(isPresented: $isShowingFilterSheet, onDismiss: { pipeline.reset() }) {
            FilterSheetView()
        }
    }
}

// MARK: - Filter Application Sheet
struct FilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ImageManager.self) private var imageManager
    @Environment(EffectsPipeline.self) private var pipeline
    
    var body: some View {
        // Create a bindable version of the pipeline to use with UI controls
        @Bindable var pipeline = pipeline

        NavigationView {
            VStack(spacing: 0) {
                // Image display area
                Group {
                    if pipeline.isProcessing {
                        // Give the ProgressView a frame so the layout doesn't jump
                        ProgressView()
                            .frame(maxWidth: .infinity, idealHeight: 350)

                    } else if let outputImage = pipeline.outputImage {
                        // Let the image size itself
                        Image(uiImage: outputImage)
                            .resizable()
                            .scaledToFit()

                    } else {
                        // Give the placeholder a frame
                        Color.gray.opacity(0.1)
                            .frame(maxWidth: .infinity, idealHeight: 350)
                    }
                }
                .padding()

                // Controls for the current effect
                Form {
                    Section("Effect Controls") {
                        effectControls(for: pipeline) // Pass the bindable pipeline
                    }
                }
                
                // Horizontal list of available effects
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(EffectsPipeline.Effect.allCases) { effect in
                            Button(action: { Task { await pipeline.changeEffect(to: effect) } }) {
                                Text(effect.rawValue)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(pipeline.currentEffect == effect ? Color.accentColor : Color.secondary.opacity(0.2))
                                    .foregroundColor(pipeline.currentEffect == effect ? .white : .primary)
                                    .cornerRadius(20)
                            }
                        }
                    }.padding()
                }.background(.thinMaterial)
            }
            .navigationTitle("Apply Filter").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let imageToSave = pipeline.outputImage {
                            imageManager.saveImage(imageToSave)
                            dismiss()
                        }
                    }.disabled(pipeline.outputImage == nil)
                }
            }
        }
    }

    /// A view that dynamically shows controls based on the selected effect.
    /// It now accepts a bindable pipeline.
    @ViewBuilder
    private func effectControls(for pipeline: EffectsPipeline) -> some View {
        @Bindable var pipeline = pipeline
        
        switch pipeline.currentEffect {
        case .JFA, .Countours:
            VStack {
                Text("Outline Thickness: \(Int(pipeline.outlineThickness))")
                Slider(value: $pipeline.outlineThickness, in: 1...50) { isEditing in
                    if !isEditing { Task { await pipeline.processImage() } }
                }
            }
            ColorPicker("Outline Color", selection: $pipeline.outlineColor)
                .onChange(of: pipeline.outlineColor) { Task { await pipeline.processImage() } }
        
        case .CircleBg:
            Toggle("Outline on Top", isOn: $pipeline.useThreeLayerEffect).onChange(of: pipeline.useThreeLayerEffect) { Task { await pipeline.processImage() } }
            VStack {
                Text("Circle Radius: \(String(format: "%.2f", pipeline.circleRadiusMultiplier))")
                Slider(value: $pipeline.circleRadiusMultiplier, in: 0.5...2.0) { isEditing in
                    if !isEditing { Task { await pipeline.processImage() } }
                }
            }
            shapeControls(for: pipeline)
            
        case .rectangleBg:
            Toggle("Outline on Top", isOn: $pipeline.useThreeLayerEffect).onChange(of: pipeline.useThreeLayerEffect) { Task { await pipeline.processImage() } }
            VStack {
                Text("Corner Radius: \(Int(pipeline.cornerRadius))")
                Slider(value: $pipeline.cornerRadius, in: 0...100) { isEditing in
                    if !isEditing { Task { await pipeline.processImage() } }
                }
            }
            shapeControls(for: pipeline)
            
        default:
            Text("No specific controls for this effect.").foregroundColor(.secondary)
        }
    }

    /// A reusable group of controls for shape-based effects.
    private func shapeControls(for pipeline: EffectsPipeline) -> some View {
        @Bindable var pipeline = pipeline
        return Group {
            VStack {
                Text("Outline Width: \(Int(pipeline.shapeOutlineWidth))")
                Slider(value: $pipeline.shapeOutlineWidth, in: 0...100) { isEditing in
                    if !isEditing { Task { await pipeline.processImage() } }
                }
            }
            ColorPicker("Background Color", selection: $pipeline.backgroundColor).onChange(of: pipeline.backgroundColor) { Task { await pipeline.processImage() } }
            ColorPicker("Outline Color", selection: $pipeline.outlineColor).onChange(of: pipeline.outlineColor) { Task { await pipeline.processImage() } }
        }
    }
}


// MARK: - Saved Images Tab
struct SavedImagesView: View {
    @Environment(ImageManager.self) private var imageManager
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    
    var body: some View {
        NavigationView {
            Group {
                if imageManager.savedImages.isEmpty {
                    VStack {
                        Image(systemName: "photo.stack").font(.largeTitle).foregroundColor(.secondary)
                        Text("No Saved Images").font(.headline).padding(.top)
                        Text("Go to the Filters tab to save your first image.").font(.subheadline).foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(imageManager.savedImages.indices, id: \.self) { index in
                                NavigationLink(destination: ImageDetailView(image: imageManager.savedImages[index])) {
                                    Image(uiImage: imageManager.savedImages[index])
                                        .resizable().aspectRatio(contentMode: .fill)
                                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                        .aspectRatio(1, contentMode: .fit).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1), lineWidth: 2))
                                }
                            }
                        }.padding()
                    }
                }
            }
            .navigationTitle("Saved Gallery")
        }
    }
}

// MARK: - Image Detail View
struct ImageDetailView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScaleValue: CGFloat = 1.0

    var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / self.lastScaleValue
                self.lastScaleValue = value
                self.scale *= delta
            }
            .onEnded { _ in
                self.lastScaleValue = 1.0
            }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(magnification)
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
