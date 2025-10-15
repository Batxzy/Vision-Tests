//
//  VisionTests.swift
//  I love testing
//
//  Created by Jose julian Lopez on 14/10/25.
//

import SwiftUI
import VisionKit
import Vision
import CoreImage.CIFilterBuiltins

func generateMatteImage(image: UIImage) async throws -> PixelBufferObservation? {
    
    guard let image = CIImage (image: image) else {
        return nil
    }
    
    let request = GeneratePersonSegmentationRequest()
    
    request.qualityLevel = .accurate
    
    let result = try await request.perform(on: image)
    
    return result
}



/*
@Observable
class EffectsPipeline {
    // Input and output properties
    var inputImage: UIImage?
    var outputImage: UIImage?
    var isProcessing = false
    var currentEffect: Effect = .none

    enum Effect: String, CaseIterable, Identifiable {
        case none = "None"
        case photoEffectProcess = "Process"
        case photoEffectNoir = "Noir"
        case photoEffectMono = "Mono"
        case photoEffectTonal = "Tonal"
        case sepiaTone = "Sepia"
        case bloom = "Bloom"
        case gaussianBlur = "Blur"

        var id: String { self.rawValue }
    }

  
    func processImage() async {
        guard let inputImage = inputImage else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Generate person segmentation mask
            guard let observation = try await generatePersonSegmentation(image: inputImage),
                  let maskCGImage = try? observation.cgImage else {
                outputImage = inputImage
                return
            }

            // Apply the effect with the mask
            if let processedImage = applyEffectWithMask(
                originalImage: inputImage,
                maskCGImage: maskCGImage,
                effect: currentEffect
            ) {
                outputImage = UIImage(cgImage: processedImage)
            } else {
                outputImage = inputImage
            }

        } catch {
            print("Error processing image: \\(error)")
            outputImage = inputImage
        }
    }

    // Generate person segmentation
    private func generatePersonSegmentation(image: UIImage) async throws -> PixelBufferObservation? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced

        let result = try await request.perform(on: ciImage)
        return result
    }

    // Apply effect with mask
    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) -> CGImage? {
        
        guard let ciOriginalImage = CIImage(image: originalImage) else { return nil }

        // Prepare mask
        var ciMaskImage = CIImage(cgImage: maskCGImage)
        let originalExtent = ciOriginalImage.extent
        ciMaskImage = ciMaskImage.transformed(by: CGAffineTransform(
            scaleX: originalExtent.width / CGFloat(maskCGImage.width),
            y: originalExtent.height / CGFloat(maskCGImage.height)
        ))

        // Apply effect to the original image
        let effectImage = applyEffect(effect, to: ciOriginalImage)

        // Create transparent background
        let transparentBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: originalExtent)

        // Blend the effect image over transparent background using the mask
        // This keeps only the person with the effect, everything else is transparent
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = effectImage
        blendFilter.backgroundImage = transparentBackground
        blendFilter.maskImage = ciMaskImage

        // Render the result with alpha channel support
        let context = CIContext()
        guard let outputImage = blendFilter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return cgImage
    }


    // Apply specific effect
    private func applyEffect(_ effect: Effect, to image: CIImage) -> CIImage {
        switch effect {
        case .none:
            return image

        case .photoEffectProcess:
            let filter = CIFilter.photoEffectProcess()
            filter.inputImage = image
            return filter.outputImage ?? image

        case .photoEffectNoir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = image
            return filter.outputImage ?? image

        case .photoEffectMono:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = image
            return filter.outputImage ?? image

        case .photoEffectTonal:
            let filter = CIFilter.photoEffectTonal()
            filter.inputImage = image
            return filter.outputImage ?? image

        case .sepiaTone:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = image
            filter.intensity = 0.8
            return filter.outputImage ?? image

        case .bloom:
            let filter = CIFilter.bloom()
            filter.inputImage = image
            filter.intensity = 0.5
            filter.radius = 10
            return filter.outputImage ?? image

        case .gaussianBlur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image
            filter.radius = 5
            return filter.outputImage ?? image
        }
    }


    func changeEffect(to effect: Effect) async {
        currentEffect = effect
        await processImage()
    }
}
*/

@Observable
class EffectsPipeline {
    var inputImage: UIImage?
    var outputImage: UIImage?
    var isProcessing = false
    var currentEffect: Effect = .none

    // Slider properties (use Double for SwiftUI Slider binding)
    var outlineThickness: Double = 15.0
    var outlineWidth: Double = 10.0

    enum Effect: String, CaseIterable, Identifiable {
        case none = "None"
        case photoEffectProcess = "Process"
        case JFA = "JumpFlood"
        case photoEffectNoir = "Noir"
        case photoEffectMono = "Mono"
        case photoEffectTonal = "Tonal"
        case sepiaTone = "Sepia"
        case bloom = "Bloom"
        case gaussianBlur = "Blur"

        var id: String { self.rawValue }
    }

    private static let outlineKernel: CIKernel = {
        do {
            guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
                  let data = try? Data(contentsOf: url) else {
                fatalError("Failed to load default.metallib")
            }
            return try CIKernel(functionName: "sdfToOutlineKernel", fromMetalLibraryData: data)
        } catch {
            fatalError("Failed to load outline kernel: \(error)")
        }
    }()

    func processImage() async {
        guard let inputImage = self.inputImage else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Get person mask
            guard let observation = try await generatePersonSegmentation(image: inputImage),
                  let maskCGImage = try? observation.cgImage else { return }

            // Apply effect and update output
            if let processedImage = applyEffectWithMask(
                originalImage: inputImage,
                maskCGImage: maskCGImage,
                effect: currentEffect
            ) {
                outputImage = UIImage(cgImage: processedImage)
            }
        } catch {
            print("Error processing image: \(error)")
            outputImage = inputImage
        }
    }

    private func generatePersonSegmentation(image: UIImage) async throws -> PixelBufferObservation? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        return try await request.perform(on: ciImage)
    }
    
    private func generateJFAOutline(from mask: CIImage) -> CIImage? {
        let extent = mask.extent
        
        // Use morphology gradient to extract edges - this is FAST and works perfectly
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = mask
        morphology.radius = Float(outlineThickness)
        
        guard let edgeImage = morphology.outputImage else { return nil }
        
        // Multiply with white color to make it visible
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = edgeImage
        colorMatrix.rVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.gVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.bVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    }

    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) -> CGImage? {
        guard let ciOriginalImage = CIImage(image: originalImage) else { return nil }

        // Scale mask to match image
        let originalExtent = ciOriginalImage.extent
        let ciMaskImage = CIImage(cgImage: maskCGImage).transformed(by: CGAffineTransform(
            scaleX: originalExtent.width / CGFloat(maskCGImage.width),
            y: originalExtent.height / CGFloat(maskCGImage.height)
        ))
        
        if effect == .JFA {
            guard let outlineImage = generateJFAOutline(from: ciMaskImage) else { return nil }
            
            // 1. Isolate the person
            let transparentBackground = CIImage.empty().cropped(to: originalExtent)
            let maskFilter = CIFilter.blendWithMask()
            maskFilter.inputImage = ciOriginalImage
            maskFilter.backgroundImage = transparentBackground
            maskFilter.maskImage = ciMaskImage
            
            guard let maskedPersonImage = maskFilter.outputImage else { return nil }
            
            // 2. Composite person OVER outline
            let compositeFilter = CIFilter.sourceOverCompositing()
            compositeFilter.inputImage = maskedPersonImage
            compositeFilter.backgroundImage = outlineImage
            
            let context = CIContext()
            guard let finalImage = compositeFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: originalExtent)
        }

        // --- Logic for other effects ---
        let effectImage = applyEffect(effect, to: ciOriginalImage)
        let transparentBackground = CIImage(color: .clear).cropped(to: originalExtent)
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = effectImage
        blendFilter.backgroundImage = transparentBackground
        blendFilter.maskImage = ciMaskImage

        let context = CIContext()
        guard let outputCIImage = blendFilter.outputImage else { return nil }
        return context.createCGImage(outputCIImage, from: outputCIImage.extent)
    }

    private func applyEffect(_ effect: Effect, to image: CIImage) -> CIImage {
        switch effect {
        case .none, .JFA:
            return image
            
        case .photoEffectProcess:
            let filter = CIFilter.photoEffectProcess()
            filter.inputImage = image
            return filter.outputImage ?? image

        case .photoEffectNoir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = image
            return filter.outputImage ?? image
            
        case .photoEffectMono:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = image
            return filter.outputImage ?? image
            
        case .photoEffectTonal:
            let filter = CIFilter.photoEffectTonal()
            filter.inputImage = image
            return filter.outputImage ?? image
            
        case .sepiaTone:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = image
            filter.intensity = 0.8
            return filter.outputImage ?? image
            
        case .bloom:
            let filter = CIFilter.bloom()
            filter.inputImage = image
            filter.intensity = 0.5
            filter.radius = 10
            return filter.outputImage ?? image
            
        case .gaussianBlur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image
            filter.radius = 5
            return filter.outputImage ?? image
        }
    }

    func changeEffect(to effect: Effect) async {
        currentEffect = effect
        await processImage()
    }
}
struct VisionTests: View {
    @State private var pipeline = EffectsPipeline()

    var body: some View {
        VStack(spacing: 16) {
            // Image display
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

            // --- SLIDERS FOR JFA EFFECT ---
            if pipeline.currentEffect == .JFA {
                VStack {
                    Text("Outline Distance: \(Int(pipeline.outlineThickness))")
                    Slider(value: $pipeline.outlineThickness, in: 1...50) { isEditing in
                        if !isEditing { // Only process when user lets go
                            Task { await pipeline.processImage() }
                        }
                    }

                    Text("Outline Width: \(Int(pipeline.outlineWidth))")
                    Slider(value: $pipeline.outlineWidth, in: 1...50) { isEditing in
                         if !isEditing { // Only process when user lets go
                            Task { await pipeline.processImage() }
                        }
                    }
                }
                .padding(.horizontal)
                .tint(.blue)
            }
            
            // Effect selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(EffectsPipeline.Effect.allCases) { effect in
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

            // Load image button
            Button(action: {
                if let image = UIImage(named: "Sports_1") { // Make sure this image is in your Assets
                    pipeline.inputImage = image
                    Task { await pipeline.processImage() } // Process immediately on load
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
        .onAppear {
             if let image = UIImage(named: "Sports_1") { // Auto-load an image
                pipeline.inputImage = image
            }
        }
    }
}


#Preview {
    VisionTests()
}
