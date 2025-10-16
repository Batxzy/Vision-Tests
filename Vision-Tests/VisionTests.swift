import SwiftUI
import VisionKit
import Vision
import CoreImage.CIFilterBuiltins



struct VisionTests: View {
    @State private var pipeline = EffectsPipeline_OG()
    
    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let outputImage = pipeline.outputImage {
                    Image(uiImage: outputImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                } else if let inputImage = pipeline.inputImage {
                    Image(uiImage: inputImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 400)
                        .overlay(Text("Load an image").foregroundColor(.gray))
                }
            }
            
            if pipeline.currentEffect == .JFA {
                VStack(spacing: 12) {
                    VStack {
                        Text("Outline Thickness: \(Int(pipeline.outlineThickness))")
                        Slider(value: $pipeline.outlineThickness, in: 1...50) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                    
                    ColorPicker("Outline Color", selection: $pipeline.outlineColor)
                        .onChange(of: pipeline.outlineColor) {
                            Task { await pipeline.processImage() }
                        }
                }
                .padding(.horizontal)
                .tint(.blue)
            }
            
            if pipeline.currentEffect == .Countours {
                VStack(spacing: 12) {
                    VStack {
                        Text("Outline Thickness: \(Int(pipeline.outlineThickness))")
                        Slider(value: $pipeline.outlineThickness, in: 1...50) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                    
                    ColorPicker("Outline Color", selection: $pipeline.outlineColor)
                        .onChange(of: pipeline.outlineColor) {
                            Task { await pipeline.processImage() }
                        }
                }
                .padding(.horizontal)
                .tint(.blue)
            }
            
            if pipeline.currentEffect == .CircleBg {
                VStack(spacing: 12) {
                    Toggle("Outline on Top", isOn: $pipeline.useThreeLayerEffect)
                        .onChange(of: pipeline.useThreeLayerEffect) {
                            Task { await pipeline.processImage() }
                        }
                    
                    VStack {
                        Text("Circle Radius: \(String(format: "%.2f", pipeline.circleRadiusMultiplier))")
                        Slider(value: $pipeline.circleRadiusMultiplier, in: 0.5...2.0) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                    
                    VStack {
                        Text("Outline Width: \(Int(pipeline.shapeOutlineWidth))")
                        Slider(value: $pipeline.shapeOutlineWidth, in: 0...100) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                    
                    ColorPicker("Background Color", selection: $pipeline.backgroundColor)
                        .onChange(of: pipeline.backgroundColor) {
                            Task { await pipeline.processImage() }
                        }
                    
                    ColorPicker("Outline Color", selection: $pipeline.outlineColor)
                        .onChange(of: pipeline.outlineColor) {
                            Task { await pipeline.processImage() }
                        }
                }
                .padding(.horizontal)
                .tint(.blue)
            }
            
            if pipeline.currentEffect == .rectangleBg {
                VStack(spacing: 12) {
                    Toggle("Outline on Top", isOn: $pipeline.useThreeLayerEffect)
                        .onChange(of: pipeline.useThreeLayerEffect) {
                            Task { await pipeline.processImage() }
                        }
                    
                    VStack {
                        Text("Corner Radius: \(Int(pipeline.cornerRadius))")
                        Slider(value: $pipeline.cornerRadius, in: 0...100) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                    
                    VStack {
                        Text("Outline Width: \(Int(pipeline.shapeOutlineWidth))")
                        Slider(value: $pipeline.shapeOutlineWidth, in: 0...100) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                    
                    ColorPicker("Background Color", selection: $pipeline.backgroundColor)
                        .onChange(of: pipeline.backgroundColor) {
                            Task { await pipeline.processImage() }
                        }
                    
                    ColorPicker("Outline Color", selection: $pipeline.outlineColor)
                        .onChange(of: pipeline.outlineColor) {
                            Task { await pipeline.processImage() }
                        }
                }
                .padding(.horizontal)
                .tint(.blue)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(EffectsPipeline_OG.Effect.allCases) { effect in
                        Button(action: {
                            Task { await pipeline.changeEffect(to: effect) }
                        }) {
                            Text(effect.rawValue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(pipeline.currentEffect == effect ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                        }
                        .disabled(pipeline.isProcessing)
                    }
                }
                .padding(.horizontal)
            }
            
            Button(action: {
                if let image = UIImage(named: "Kpop") {
                    pipeline.inputImage = image
                    Task { await pipeline.processImage() }
                }
            }) {
                Label("Load Image", systemImage: "photo")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(pipeline.isProcessing)
        }
        .padding()
    }
}

#Preview {
    VisionTests()
}
