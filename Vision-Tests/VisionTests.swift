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

    private static let jfaKernels: (seed: CIKernel, pass: CIKernel, outline: CIKernel) = {
            do {
                guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
                      let data = try? Data(contentsOf: url) else {
                    fatalError("Failed to load default.metallib. Check if JFAKernels.metal is in the build target.")
                }
                let seedKernel = try CIKernel(functionName: "seedKernel", fromMetalLibraryData: data)
                let passKernel = try CIKernel(functionName: "jfaPassKernel", fromMetalLibraryData: data)
                let outlineKernel = try CIKernel(functionName: "sdfToOutlineKernel", fromMetalLibraryData: data)
                return (seedKernel, passKernel, outlineKernel)
            } catch {
                fatalError("Failed to load JFA kernels: \(error)")
            }
    }()
    
    
    func processImage() async {
        let inputImage = self.inputImage!

        isProcessing = true
        
        defer { isProcessing = false }

        // Get person mask
        let observation = try! await generatePersonSegmentation(image: inputImage)
        
        let maskCGImage = try! observation!.cgImage

        // Apply effect and update output
        let processedImage = applyEffectWithMask(
            originalImage: inputImage,
            maskCGImage: maskCGImage,
            effect: currentEffect
        )

        outputImage = UIImage(cgImage: processedImage!)
    }

    private func generatePersonSegmentation(image: UIImage) async throws -> PixelBufferObservation? {
        let ciImage = CIImage(image: image)!

        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced

        return try await request.perform(on: ciImage)
    }

    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) -> CGImage? {
        let ciOriginalImage = CIImage(image: originalImage)!

        // Scale mask to match image
        let originalExtent = ciOriginalImage.extent
        let ciMaskImage = CIImage(cgImage: maskCGImage).transformed(by: CGAffineTransform(
            scaleX: originalExtent.width / CGFloat(maskCGImage.width),
            y: originalExtent.height / CGFloat(maskCGImage.height)
        ))
        
        if effect == .JFA {
                    // 1. Generate the outline from the mask
                    guard let outlineImage = generateJFAOutline(from: ciMaskImage) else { return nil }

                    // 2. Composite the outline over the original image
                    let compositeFilter = CIFilter.sourceOverCompositing()
                    compositeFilter.inputImage = outlineImage
                    compositeFilter.backgroundImage = ciOriginalImage
                    
                    let context = CIContext()
                    return context.createCGImage(compositeFilter.outputImage!, from: originalExtent)
                }

        // Apply effect
        let effectImage = applyEffect(effect, to: ciOriginalImage)

        // Create transparent background
        let transparentBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: originalExtent)

        // Blend with mask
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = effectImage
        blendFilter.backgroundImage = transparentBackground
        blendFilter.maskImage = ciMaskImage

        // Render
        let context = CIContext()
        return context.createCGImage(blendFilter.outputImage!, from: blendFilter.outputImage!.extent)
    }
    
    private func generateJFAOutline(from mask: CIImage) -> CIImage? {
           let extent = mask.extent
           
           // 1. Create the initial seed image using our custom kernel
           var currentPass = EffectsPipeline.jfaKernels.seed.apply(
               extent: extent,
               roiCallback: { _, r in r },
               arguments: [mask]
           )!
           
           // 2. Run the JFA passes, halving the jump distance each time
           let maxDimension = max(extent.width, extent.height)
           var jumpDistance = Float(pow(2, floor(log2(maxDimension))))
           
           while jumpDistance >= 1 {
               currentPass = EffectsPipeline.jfaKernels.pass.apply(
                   extent: extent,
                   roiCallback: { _, r in r },
                   arguments: [currentPass, jumpDistance]
               )!
               jumpDistance /= 2
           }
           
           // 3. Render the final outline from the completed SDF
           let outline = EffectsPipeline.jfaKernels.outline.apply(
               extent: extent,
               roiCallback: { _, r in r },
               arguments: [
                   currentPass,
                   5.0, // Thickness
                   2.0, // Softness
                   CIColor.white // Outline Color
               ]
           )
           
           return outline
       }

    private func applyEffect(_ effect: Effect, to image: CIImage) -> CIImage {
        switch effect {
        case .none:
            return image
            
        case .JFA:
            return image
            
        case .photoEffectProcess:
            let filter = CIFilter.photoEffectProcess()
            filter.inputImage = image
            return filter.outputImage!

        case .photoEffectNoir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = image
            return filter.outputImage!

        case .photoEffectMono:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = image
            return filter.outputImage!

        case .photoEffectTonal:
            let filter = CIFilter.photoEffectTonal()
            filter.inputImage = image
            return filter.outputImage!

        case .sepiaTone:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = image
            filter.intensity = 0.8
            return filter.outputImage!

        case .bloom:
            let filter = CIFilter.bloom()
            filter.inputImage = image
            filter.intensity = 0.5
            filter.radius = 10
            return filter.outputImage!

        case .gaussianBlur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image
            filter.radius = 5
            return filter.outputImage!
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
            VStack(spacing: 20) {
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
                            .overlay(
                                Text("Load an image")
                                    .foregroundColor(.gray)
                            )
                    }
                }

                // Effect selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(EffectsPipeline.Effect.allCases) { effect in
                            Button(action: {
                                Task {
                                    await pipeline.changeEffect(to: effect)
                                }
                            }) {
                                Text(effect.rawValue)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        pipeline.currentEffect == effect ?
                                        Color.blue : Color.gray.opacity(0.3)
                                    )
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
                    // Load from assets for now
                    if let image = UIImage(named: "Sports_1") {
                        pipeline.inputImage = image
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
                // Auto-load image on appear if you want
                if let image = UIImage(named: "picture") {
                    pipeline.inputImage = image
                }
            }
        }
    }


#Preview {
    VisionTests()
}
