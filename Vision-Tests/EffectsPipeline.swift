//
//  EffectsPipeline.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 15/10/25.
//

import SwiftUI
import VisionKit
import Vision
import CoreImage.CIFilterBuiltins

@Observable
class EffectsPipeline {
    // MARK: - State Properties
    var inputImage: UIImage?
    var outputImage: UIImage?
    var isProcessing = false
    var currentEffect: Effect = .none
    
    // MARK: - Effect Parameters
    var outlineThickness: Double = 15.0
    var cornerRadius: Double = 20.0
    var circleRadiusMultiplier: Double = 1.1
    var shapeOutlineWidth: Double = 5.0
    var backgroundColor: Color = .white
    var outlineColor: Color = .black
    var useThreeLayerEffect: Bool = false
    
    enum Effect: String, CaseIterable, Identifiable {
        case none = "None", photoEffectProcess = "Process", JFA = "JumpFlood",
             Countours = "Contours", CircleBg = "Circle BG", rectangleBg = "Rectangle BG",
             photoEffectNoir = "Noir", photoEffectMono = "Mono", photoEffectTonal = "Tonal",
             sepiaTone = "Sepia", bloom = "Bloom", gaussianBlur = "Blur"
        var id: String { self.rawValue }
    }
    
    func reset() {
        inputImage = nil
        outputImage = nil
        currentEffect = .none
        isProcessing = false
    }
    
    func changeEffect(to effect: Effect) async {
        currentEffect = effect
        await processImage()
    }
    
    // MARK: - Core Processing Logic
    
    func processImage() async {
        guard let inputImage = self.inputImage else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let request = GeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            let observation = try await request.perform(on: CIImage(image: inputImage)!)
            
            guard let maskCGImage = try? observation.cgImage else {
                outputImage = inputImage; return
            }
            
            if let processedImage = await applyEffectWithMask(originalImage: inputImage, maskCGImage: maskCGImage, effect: currentEffect) {
                outputImage = UIImage(cgImage: processedImage)
            }
        } catch {
            print("Error processing image: \(error)"); outputImage = inputImage
        }
    }
    
    // MARK: - Vision Helpers
    
    private func cleanSegmentationMask(_ maskCGImage: CGImage, targetSize: CGSize) -> CIImage? {
        var ciMask = CIImage(cgImage: maskCGImage)
        
        ciMask = ciMask.transformed(by: CGAffineTransform(
            scaleX: targetSize.width / CGFloat(maskCGImage.width),
            y: targetSize.height / CGFloat(maskCGImage.height)
        ))
        
        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = ciMask
        threshold.threshold = 0.5
        guard let thresholded = threshold.outputImage else { return nil }
        
        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = thresholded
        dilate.radius = 3.0
        guard let dilated = dilate.outputImage else { return nil }
        
        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = dilated
        erode.radius = 2.0
        guard let eroded = erode.outputImage else { return nil }
        
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

    private func detectSaliency(from image: UIImage) async throws -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let saliency = request.results?.first, let salientObjects = saliency.salientObjects, !salientObjects.isEmpty else { return nil }
        
        return salientObjects.dropFirst().reduce(salientObjects[0].boundingBox) { partialResult, nextObservation in
            partialResult.union(nextObservation.boundingBox)
        }
    }
    
    // MARK: - Image Generation Helpers
    
    private func pathToCIImage(_ path: CGPath, in extent: CGRect, strokeWidth: CGFloat, color: UIColor) -> CIImage? {
        let renderer = UIGraphicsImageRenderer(size: extent.size)
        let image = renderer.image { context in
            context.cgContext.setStrokeColor(color.cgColor)
            context.cgContext.setLineWidth(strokeWidth)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            var transform = CGAffineTransform(scaleX: extent.width, y: -extent.height).translatedBy(x: 0, y: -1)
            if let scaledPath = path.copy(using: &transform) {
                context.cgContext.addPath(scaledPath)
                context.cgContext.strokePath()
            }
        }
        return CIImage(image: image)
    }
    
    private func drawCircle(in canvasFrame: CGRect, withShapeFrame shapeFrame: CGRect, color: UIColor) -> CIImage? {
        let renderer = UIGraphicsImageRenderer(size: canvasFrame.size)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -canvasFrame.origin.x, y: -canvasFrame.origin.y)
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fillEllipse(in: shapeFrame)
        }
        guard let ciImage = CIImage(image: image) else { return nil }
        return ciImage.transformed(by: CGAffineTransform(translationX: canvasFrame.origin.x, y: canvasFrame.origin.y))
    }

    private func drawRectangle(in canvasFrame: CGRect, withShapeFrame shapeFrame: CGRect, cornerRadius: CGFloat, color: UIColor) -> CIImage? {
        let renderer = UIGraphicsImageRenderer(size: canvasFrame.size)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -canvasFrame.origin.x, y: -canvasFrame.origin.y)
            let path = UIBezierPath(roundedRect: shapeFrame, cornerRadius: cornerRadius)
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
        }
        guard let ciImage = CIImage(image: image) else { return nil }
        return ciImage.transformed(by: CGAffineTransform(translationX: canvasFrame.origin.x, y: canvasFrame.origin.y))
    }

    private func generateJFAOutline(from mask: CIImage, color: Color) -> CIImage? {
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = mask
        morphology.radius = Float(outlineThickness)
        guard let edgeImage = morphology.outputImage else { return nil }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = edgeImage
        blur.radius = 3.0
        guard let blurredEdge = blur.outputImage else { return nil }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = blurredEdge
        colorMatrix.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        return colorMatrix.outputImage
    }

    private func generateShapeOutline(from shape: CIImage, color: Color) -> CIImage? {
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        guard let edgeImage = morphology.outputImage else { return nil }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = edgeImage
        colorMatrix.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        return colorMatrix.outputImage
    }
    
    // MARK: - Main Effect Logic

    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) async -> CGImage? {
        guard let ciOriginalImage = CIImage(image: originalImage) else { return nil }
        let originalExtent = ciOriginalImage.extent
        guard let ciMaskImage = cleanSegmentationMask(maskCGImage, targetSize: originalExtent.size) else { return nil }
        let context = CIContext()
        
        let maskedPerson = ciOriginalImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.clear.cropped(to: originalExtent),
            kCIInputMaskImageKey: ciMaskImage
        ])

        switch effect {
        case .JFA:
            guard let outlineImage = generateJFAOutline(from: ciMaskImage, color: outlineColor) else { return nil }
            return composite(layers: [outlineImage, maskedPerson], context: context)
            
        case .Countours:
            // Unwrap the optional CGPath returned by detectContours only once.
            guard let contoursPath = try? await detectContours(from: maskCGImage),
                  let outlineImage = pathToCIImage(contoursPath, in: originalExtent, strokeWidth: outlineThickness, color: UIColor(outlineColor)) else {
                return nil
            }
            return composite(layers: [outlineImage, maskedPerson], context: context)

        case .CircleBg:
            guard let boundingBox = try? await detectSaliency(from: originalImage) else { return nil }
            
            let center = CGPoint(x: boundingBox.midX * originalExtent.width, y: (1 - boundingBox.midY) * originalExtent.height)
            let radius = max(boundingBox.width * originalExtent.width, boundingBox.height * originalExtent.height) / 2 * circleRadiusMultiplier
            let shapeFrame = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let canvasFrame = shapeFrame.insetBy(dx: -shapeOutlineWidth * 2, dy: -shapeOutlineWidth * 2).integral
            
            guard let background = drawCircle(in: canvasFrame, withShapeFrame: shapeFrame, color: UIColor(backgroundColor)),
                  let mask = drawCircle(in: canvasFrame, withShapeFrame: shapeFrame, color: .white),
                  let outline = generateShapeOutline(from: background, color: outlineColor) else { return nil }
            
            let paddedPerson = maskedPerson.composited(over: CIImage.clear.cropped(to: canvasFrame))
            let clippedPerson = paddedPerson.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.clear.cropped(to: paddedPerson.extent),
                kCIInputMaskImageKey: mask
            ])
            
            let layers = useThreeLayerEffect ? [background, outline, clippedPerson] : [outline, background, clippedPerson]
            return composite(layers: layers, context: context)

        case .rectangleBg:
            guard let boundingBox = try? await detectSaliency(from: originalImage) else { return nil }
            
            let padding: CGFloat = 0.05
            let paddedBox = CGRect(x: max(0, boundingBox.minX - padding), y: max(0, boundingBox.minY - padding), width: min(1.0, boundingBox.width + padding * 2), height: min(1.0, boundingBox.height + padding * 2))
            let shapeFrame = CGRect(x: paddedBox.minX * originalExtent.width, y: (1 - paddedBox.maxY) * originalExtent.height, width: paddedBox.width * originalExtent.width, height: paddedBox.height * originalExtent.height)
            let canvasFrame = shapeFrame.insetBy(dx: -shapeOutlineWidth * 2, dy: -shapeOutlineWidth * 2).integral

            guard let background = drawRectangle(in: canvasFrame, withShapeFrame: shapeFrame, cornerRadius: cornerRadius, color: UIColor(backgroundColor)),
                  let mask = drawRectangle(in: canvasFrame, withShapeFrame: shapeFrame, cornerRadius: cornerRadius, color: .white),
                  let outline = generateShapeOutline(from: background, color: outlineColor) else { return nil }
            
            let paddedPerson = maskedPerson.composited(over: CIImage.clear.cropped(to: canvasFrame))
            let clippedPerson = paddedPerson.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.clear.cropped(to: paddedPerson.extent),
                kCIInputMaskImageKey: mask
            ])

            let layers = useThreeLayerEffect ? [background, outline, clippedPerson] : [outline, background, clippedPerson]
            return composite(layers: layers, context: context)

        default:
            return applyStandardEffect(effect: effect, original: ciOriginalImage, mask: ciMaskImage, extent: originalExtent, context: context)
        }
    }
    
    private func composite(layers: [CIImage], context: CIContext) -> CGImage? {
        guard !layers.isEmpty else { return nil }
        var finalImage = layers.first!
        for i in 1..<layers.count {
            finalImage = layers[i].composited(over: finalImage)
        }
        return context.createCGImage(finalImage, from: finalImage.extent)
    }
    
    // MARK: - Standard Effects
    
    private func applyStandardEffect(effect: Effect, original: CIImage, mask: CIImage, extent: CGRect, context: CIContext) -> CGImage? {
        let effectImage = applyEffect(effect, to: original)
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = effectImage
        blendFilter.backgroundImage = CIImage.clear.cropped(to: extent)
        blendFilter.maskImage = mask
        guard let outputCIImage = blendFilter.outputImage else { return nil }
        return context.createCGImage(outputCIImage, from: outputCIImage.extent)
    }
    
    private func applyEffect(_ effect: Effect, to image: CIImage) -> CIImage {
        switch effect {
        case .none, .JFA, .Countours, .CircleBg, .rectangleBg:
            return image
        case .photoEffectProcess:
            let filter = CIFilter.photoEffectProcess(); filter.inputImage = image; return filter.outputImage ?? image
        case .photoEffectNoir:
            let filter = CIFilter.photoEffectNoir(); filter.inputImage = image; return filter.outputImage ?? image
        case .photoEffectMono:
            let filter = CIFilter.photoEffectMono(); filter.inputImage = image; return filter.outputImage ?? image
        case .photoEffectTonal:
            let filter = CIFilter.photoEffectTonal(); filter.inputImage = image; return filter.outputImage ?? image
        case .sepiaTone:
            let filter = CIFilter.sepiaTone(); filter.inputImage = image; filter.intensity = 0.8; return filter.outputImage ?? image
        case .bloom:
            let filter = CIFilter.bloom(); filter.inputImage = image; filter.intensity = 0.5; filter.radius = 10; return filter.outputImage ?? image
        case .gaussianBlur:
            let filter = CIFilter.gaussianBlur(); filter.inputImage = image; filter.radius = 5; return filter.outputImage ?? image
        }
    }
}
