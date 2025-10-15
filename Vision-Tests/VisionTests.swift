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
    
    var outlineThickness: Double = 15.0
    var outlineWidth: Double = 10.0
    
    enum Effect: String, CaseIterable, Identifiable {
        case none = "None"
        case photoEffectProcess = "Process"
        case JFA = "JumpFlood"
        case Countours = "countours"
        case CircleBg = "circle backgroudnd"
        case rectangleBg = "rectangle backgroudnd"
        case photoEffectNoir = "Noir"
        case photoEffectMono = "Mono"
        case photoEffectTonal = "Tonal"
        case sepiaTone = "Sepia"
        case bloom = "Bloom"
        case gaussianBlur = "Blur"
        
        var id: String { self.rawValue }
    }
    
    func processImage() async {
        guard let inputImage = self.inputImage else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            guard let observation = try await generatePersonSegmentation(image: inputImage),
                  let maskCGImage = try? observation.cgImage else { return }
            
            if let processedImage = await applyEffectWithMask(
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
        request.qualityLevel = .accurate  // Highest quality
        
        return try await request.perform(on: ciImage)
    }
    
    private func cleanSegmentationMask(_ maskCGImage: CGImage, targetSize: CGSize) -> CIImage? {
        var ciMask = CIImage(cgImage: maskCGImage)
        
        // Scale to full resolution
        ciMask = ciMask.transformed(by: CGAffineTransform(
            scaleX: targetSize.width / CGFloat(maskCGImage.width),
            y: targetSize.height / CGFloat(maskCGImage.height)
        ))
        
        // 1. Aggressive threshold to remove ghosting
        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = ciMask
        threshold.threshold = 0.5
        
        guard let thresholded = threshold.outputImage else { return nil }
        
        // 2. Close small holes
        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = thresholded
        dilate.radius = 3.0
        
        guard let dilated = dilate.outputImage else { return nil }
        
        // 3. Smooth edges
        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = dilated
        erode.radius = 2.0
        
        guard let eroded = erode.outputImage else { return nil }
        
        // 4. Slight blur for anti-aliasing
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = eroded
        blur.radius = 1.5
        
        return blur.outputImage
    }
    
    private func detectContours(from maskCGImage: CGImage) async throws -> CGPath? {
        var request = DetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = false
        
        let maskImage = CIImage(cgImage: maskCGImage)
        let observation = try await request.perform(on: maskImage, orientation: .up)
        
        return observation.normalizedPath
    }
    
    
    private func pathToCIImage(_ path: CGPath, in extent: CGRect, strokeWidth: CGFloat) -> CIImage? {
        // Use scale of 1.0 to match CIImage coordinate space
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Critical: force scale to 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(strokeWidth)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            
            // Simple transform for normalized coordinates
            var transform = CGAffineTransform(scaleX: extent.width, y: -extent.height)
                .translatedBy(x: 0, y: -1)
            
            if let scaledPath = path.copy(using: &transform) {
                context.cgContext.addPath(scaledPath)
                context.cgContext.strokePath()
            }
        }
        
        return CIImage(image: image)
    }
    
    private func generateJFAOutline(from mask: CIImage) -> CIImage? {
        // 1. Generate outline with morphology gradient
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = mask
        morphology.radius = Float(outlineThickness)
        
        guard let edgeImage = morphology.outputImage else { return nil }
        
        // 2. Soften the edges with Gaussian blur
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = edgeImage
        blur.radius = 3.0
        
        guard let blurredEdge = blur.outputImage else { return nil }
        
        // 3. Make it white
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = blurredEdge
        colorMatrix.rVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.gVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.bVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    }
    
    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) async -> CGImage? {
        guard let ciOriginalImage = CIImage(image: originalImage) else { return nil }
        
        let originalExtent = ciOriginalImage.extent
        
        guard let ciMaskImage = cleanSegmentationMask(maskCGImage, targetSize: originalExtent.size) else {
            return nil
        }
        
        
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
            
        }  else if effect == .Countours {
            let context = CIContext()
            
            guard let cleanedMaskCGImage = context.createCGImage(ciMaskImage, from: originalExtent) else {
                return nil
            }
            
            // Llama a la versión simple de detectContours
            guard let path = try? await detectContours(from: cleanedMaskCGImage),
                  let outlineImage = pathToCIImage(path, in: originalExtent, strokeWidth: outlineThickness) else {
                return nil
            }
            
            let transparentBackground = CIImage.empty().cropped(to: originalExtent)
            let maskFilter = CIFilter.blendWithMask()
            maskFilter.inputImage = ciOriginalImage
            maskFilter.backgroundImage = transparentBackground
            maskFilter.maskImage = ciMaskImage
            
            guard let maskedPersonImage = maskFilter.outputImage else { return nil }
            
            let compositeFilter = CIFilter.sourceOverCompositing()
            compositeFilter.inputImage = maskedPersonImage
            compositeFilter.backgroundImage = outlineImage
            
            guard let finalImage = compositeFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: originalExtent)
        }
        
        // Other effects
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
        case .none, .JFA,.Countours:
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
            
            // Sliders for JFA effect
            if pipeline.currentEffect == .JFA {
                VStack {
                    Text("Outline Thickness: \(Int(pipeline.outlineThickness))")
                    Slider(value: $pipeline.outlineThickness, in: 1...50) { isEditing in
                        if !isEditing {
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
                if let image = UIImage(named: "Sporty") {
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
