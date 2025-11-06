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
    var cornerRadius: Double = 5.0
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
    
    // Resets the pipeline's state, clearing any loaded images.
    func reset() {
        inputImage = nil
        outputImage = nil
        currentEffect = .none
        isProcessing = false
    }

    // Sets a new effect and triggers processing.
    func changeEffect(to effect: Effect) async {
        currentEffect = effect
        await processImage()
    }
    
    // MARK: - Core Processing Logic (No changes from your original logic)
    
    
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

    // MARK: - Funciones que se comunican con Vision y cositas

    private func generatePersonSegmentation(image: UIImage) async throws -> PixelBufferObservation? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        
        return try await request.perform(on: ciImage)
    }
    
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

    
    private func detectHumanRectangles(from image: UIImage) async throws -> CGRect? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        var request = DetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        
        let observations = try await request.perform(on: ciImage)
        guard !observations.isEmpty else { return nil }
        
        // HumanObservation conforms to BoundingBoxProviding, has boundingBox: NormalizedRect
        let firstBox = observations[0].boundingBox
        var unionBox = CGRect(
            x: CGFloat(firstBox.origin.x),
            y: CGFloat(firstBox.origin.y),
            width: CGFloat(firstBox.width),  // NOT firstBox.size.width
            height: CGFloat(firstBox.height) // NOT firstBox.size.height
        )
        
        for i in 1..<observations.count {
            let box = observations[i].boundingBox
            let rect = CGRect(
                x: CGFloat(box.origin.x),
                y: CGFloat(box.origin.y),
                width: CGFloat(box.width),
                height: CGFloat(box.height)
            )
            unionBox = unionBox.union(rect)
        }
        
        return unionBox
    }

    private func detectSaliency(from image: UIImage) async throws -> CGRect? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        let request = GenerateAttentionBasedSaliencyImageRequest()
        let observation = try await request.perform(on: ciImage)
        
        let salientObjects = observation.salientObjects
        guard !salientObjects.isEmpty else { return nil }
        
        let firstBox = salientObjects[0].boundingBox
        var unionBox = CGRect(
            x: CGFloat(firstBox.origin.x),
            y: CGFloat(firstBox.origin.y),
            width: CGFloat(firstBox.width),
            height: CGFloat(firstBox.height)
        )
        
        for i in 1..<salientObjects.count {
            let box = salientObjects[i].boundingBox
            let rect = CGRect(
                x: CGFloat(box.origin.x),
                y: CGFloat(box.origin.y),
                width: CGFloat(box.width),
                height: CGFloat(box.height)
            )
            unionBox = unionBox.union(rect)
        }
        
        return unionBox
    }
    
    private func pathToCIImage(_ path: CGPath, in extent: CGRect, strokeWidth: CGFloat, color: UIColor) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            context.cgContext.setStrokeColor(color.cgColor)
            context.cgContext.setLineWidth(strokeWidth)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            
            var transform = CGAffineTransform(scaleX: extent.width, y: -extent.height)
                .translatedBy(x: 0, y: -1)
            
            if let scaledPath = path.copy(using: &transform) {
                context.cgContext.addPath(scaledPath)
                context.cgContext.strokePath()
            }
        }
        
        return CIImage(image: image)
    }
    
    private func circleToCIImage(boundingBox: CGRect, in extent: CGRect, color: UIColor) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            let center = CGPoint(
                x: boundingBox.midX * extent.width,
                y: (1 - boundingBox.midY) * extent.height
            )
            
            let radius = max(boundingBox.width * extent.width, boundingBox.height * extent.height) / 2 * circleRadiusMultiplier
            
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fillEllipse(in: rect)
        }
        
        return CIImage(image: image)
    }
    
    private func roundedRectangleToCIImage(boundingBox: CGRect, cornerRadius: CGFloat, in extent: CGRect, color: UIColor) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            let padding: CGFloat = 0.05
            let paddedBox = CGRect(
                x: max(0, boundingBox.minX - padding),
                y: max(0, boundingBox.minY - padding),
                width: min(1.0, boundingBox.width + padding * 2),
                height: min(1.0, boundingBox.height + padding * 2)
            )
            
            let rect = CGRect(
                x: paddedBox.minX * extent.width,
                y: (1 - paddedBox.maxY) * extent.height,
                width: paddedBox.width * extent.width,
                height: paddedBox.height * extent.height
            )
            
            // Scale corner radius: 1-10 scale → 30-300px
            let scaledCornerRadius = cornerRadius * 30
            let path = UIBezierPath(roundedRect: rect, cornerRadius: scaledCornerRadius)
            
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
        }
        
        return CIImage(image: image)
    }

    
    private func createCircleMask(boundingBox: CGRect, in extent: CGRect) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            let center = CGPoint(
                x: boundingBox.midX * extent.width,
                y: (1 - boundingBox.midY) * extent.height
            )
            
            let radius = max(boundingBox.width * extent.width, boundingBox.height * extent.height) / 2 * circleRadiusMultiplier
            
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: rect)
        }
        
        return CIImage(image: image)
    }
    
    private func createRectangleMask(boundingBox: CGRect, cornerRadius: CGFloat, in extent: CGRect) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            let padding: CGFloat = 0.05
            let paddedBox = CGRect(
                x: max(0, boundingBox.minX - padding),
                y: max(0, boundingBox.minY - padding),
                width: min(1.0, boundingBox.width + padding * 2),
                height: min(1.0, boundingBox.height + padding * 2)
            )
            
            let rect = CGRect(
                x: paddedBox.minX * extent.width,
                y: (1 - paddedBox.maxY) * extent.height,
                width: paddedBox.width * extent.width,
                height: paddedBox.height * extent.height
            )
            
            // Scale corner radius: 1-10 scale → 30-300px
            let scaledCornerRadius = cornerRadius * 30
            let path = UIBezierPath(roundedRect: rect, cornerRadius: scaledCornerRadius)
            
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
        }
        
        return CIImage(image: image)
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
        colorMatrix.rVector = CIVector(x: r, y: r, z: r, w: 0)
        colorMatrix.gVector = CIVector(x: g, y: g, z: g, w: 0)
        colorMatrix.bVector = CIVector(x: b, y: b, z: b, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    }

    // y este como generaba colores
    private func generateShapeOutline(from shape: CIImage, color: Color) -> CIImage? {
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        
        guard let edgeImage = morphology.outputImage else { return nil }
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = edgeImage
        colorMatrix.rVector = CIVector(x: r, y: r, z: r, w: 0)
        colorMatrix.gVector = CIVector(x: g, y: g, z: g, w: 0)
        colorMatrix.bVector = CIVector(x: b, y: b, z: b, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    }
    
    private func generateShapeOutlineSolid(from shape: CIImage, color: Color) -> CIImage? {
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        guard let edgeImage = morphology.outputImage else { return nil }
        
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = edgeImage
        thresholdFilter.threshold = 0.01
        guard let hardEdgeMask = thresholdFilter.outputImage else { return nil }
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let solidColor = CIImage(color: CIColor(red: r, green: g, blue: b, alpha: a))
            .cropped(to: shape.extent)
        
        let blendWithMask = CIFilter.blendWithMask()
        blendWithMask.inputImage = solidColor
        blendWithMask.backgroundImage = CIImage.clear.cropped(to: shape.extent)
        blendWithMask.maskImage = hardEdgeMask
        
        return blendWithMask.outputImage
    }
    
     /*private func generateShapeOutline(from shape: CIImage, color: Color) -> CIImage? {
        // 1. Create the soft-edged gradient, exactly as you had it.
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        guard let edgeImage = morphology.outputImage else { return nil }
        
        // 2. THRESHOLD STEP: Convert the soft gradient to a hard edge.
        // This filter makes every pixel below the threshold black (transparent)
        // and every pixel above it white (opaque), eliminating the gray areas.
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = edgeImage
        thresholdFilter.threshold = 0.01 // A low value ensures we capture the entire outline.
        guard let hardEdgeImage = thresholdFilter.outputImage else { return nil }
        
        // 3. Color the new hard-edged outline using your original colorMatrix logic.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = hardEdgeImage // <- We use the thresholded image here.
        colorMatrix.rVector = CIVector(x: r, y: r, z: r, w: 0)
        colorMatrix.gVector = CIVector(x: g, y: g, z: g, w: 0)
        colorMatrix.bVector = CIVector(x: b, y: b, z: b, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    } */
    
    
    /*private func generateShapeOutline(from shape: CIImage, color: Color) -> CIImage? {
        // 1. Create the soft-edged gradient.
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        guard let edgeImage = morphology.outputImage else { return nil }
        
        // 2. Threshold the gradient. The result is a white ring on a solid black background.
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = edgeImage
        thresholdFilter.threshold = 0.01
        guard let hardEdgeOpaqueMask = thresholdFilter.outputImage else { return nil }
        
        // 3. *** THE FIX ***
        // Convert the mask's luminance to alpha. This crucial step turns the
        // solid black background into a transparent one, leaving only the white ring.
        let maskToAlphaFilter = CIFilter.maskToAlpha()
        maskToAlphaFilter.inputImage = hardEdgeOpaqueMask
        guard let hardEdgeTransparentMask = maskToAlphaFilter.outputImage else { return nil }
        
        // 4. Color the corrected mask. Your colorMatrix logic now works perfectly
        // because it's operating on a clean mask with a transparent background.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = hardEdgeTransparentMask // Use the corrected mask
        colorMatrix.rVector = CIVector(x: r, y: r, z: r, w: 0)
        colorMatrix.gVector = CIVector(x: g, y: g, z: g, w: 0)
        colorMatrix.bVector = CIVector(x: b, y: b, z: b, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    } */
    
    /*private func generateShapeOutline(from shape: CIImage, color: Color) -> CIImage? {
        // 1. Create the soft-edged gradient. (No change)
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        guard let edgeImage = morphology.outputImage else { return nil }
        
        // 2. Threshold the gradient to get a hard edge. (No change)
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = edgeImage
        thresholdFilter.threshold = 0.01
        guard let hardEdgeImage = thresholdFilter.outputImage else { return nil }
        
        // 3. Color the mask using the colorMatrix.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = hardEdgeImage
        
        // --- FINAL FIX ---
        // The r, g, and b vectors are zeroed out so that the color comes
        // purely from the biasVector.
        colorMatrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        
        // This is the key change. We tell the filter to use the mask's
        // brightness (we'll use the red channel's value) to set the output alpha.
        // Black pixels (value 0) will become transparent. White pixels (value 1)
        // will become opaque.
        colorMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0) // Use Red channel for Alpha
        
        // The biasVector adds our desired color.
        colorMatrix.biasVector = CIVector(x: r, y: g, z: b, w: 0)
        
        return colorMatrix.outputImage
    } */
    
    
    //esta m gusto como se hizo los colores ya solidos
    /*private func generateShapeOutline(from shape: CIImage, color: Color) -> CIImage? {

        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        guard let edgeImage = morphology.outputImage else { return nil }
        
        
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = edgeImage
        thresholdFilter.threshold = 0.01
        guard let hardEdgeMask = thresholdFilter.outputImage else { return nil }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let solidColor = CIImage(color: CIColor(red: r, green: g, blue: b, alpha: a))
            .cropped(to: shape.extent)
            
        let blendWithMask = CIFilter.blendWithMask()
        blendWithMask.inputImage = solidColor
        blendWithMask.backgroundImage = CIImage.clear.cropped(to: shape.extent)
        blendWithMask.maskImage = hardEdgeMask
        
        return blendWithMask.outputImage
    } */
    
    private func expandedExtent(_ original: CGRect, padding: CGFloat) -> CGRect {
        return CGRect(
            x: original.minX - padding,
            y: original.minY - padding,
            width: original.width + (padding * 2),
            height: original.height + (padding * 2)
        )
    }
    private func calculateRequiredPadding() -> CGFloat {
        let outlinePadding = max(shapeOutlineWidth, outlineThickness) * 2
        let morphologyPadding = Float(max(shapeOutlineWidth, outlineThickness)) * 1.5
        let blurPadding: CGFloat = 3.0
        let circlePadding = (circleRadiusMultiplier - 1.0) * 100
        
        return outlinePadding + CGFloat(morphologyPadding) + blurPadding + circlePadding + 20
    }
    
    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) async -> CGImage? {
        guard let ciOriginalImage = CIImage(image: originalImage) else { return nil }
        let originalExtent = ciOriginalImage.extent
        guard let ciMaskImage = cleanSegmentationMask(maskCGImage, targetSize: originalExtent.size) else { return nil }
        let context = CIContext()
        
        switch effect {
        case .JFA:
            return await applyJFAEffect(original: ciOriginalImage, originalImage: originalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        case .Countours:
            return await applyContoursEffect(original: ciOriginalImage, originalImage: originalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        case .CircleBg:
            return await applyCircleBgEffect(original: ciOriginalImage, originalImage: originalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        case .rectangleBg:
            return await applyRectangleBgEffect(original: ciOriginalImage, originalImage: originalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        default:
            return applyStandardEffect(effect: effect, original: ciOriginalImage, mask: ciMaskImage, extent: originalExtent, context: context)
        }
    }
    
    private func applyJFAEffect(original: CIImage, originalImage: UIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        let canvasSize: CGFloat = 2000
        let canvasExtent = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        
        let targetSize = canvasSize * 0.9
        let scale = min(targetSize / extent.width, targetSize / extent.height)
        
        let scaledOriginal = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let scaledExtent = scaledOriginal.extent
        
        let offsetX = (canvasSize - scaledExtent.width) / 2
        let offsetY = (canvasSize - scaledExtent.height) / 2
        
        let centeredOriginal = scaledOriginal.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        let centeredMask = scaledMask.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        let blackBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: canvasExtent)
        let expandedMask = centeredMask.composited(over: blackBackground)
        
        guard let outlineImage = generateJFAOutline(from: expandedMask, color: outlineColor) else { return nil }
        
        let transparentBackground = CIImage.empty().cropped(to: canvasExtent)
        let maskFilter = CIFilter.blendWithMask()
        maskFilter.inputImage = centeredOriginal
        maskFilter.backgroundImage = transparentBackground
        maskFilter.maskImage = centeredMask
        
        guard let maskedPersonImage = maskFilter.outputImage else { return nil }
        
        let compositeFilter = CIFilter.sourceOverCompositing()
        compositeFilter.inputImage = maskedPersonImage
        compositeFilter.backgroundImage = outlineImage
        
        guard let finalImage = compositeFilter.outputImage else { return nil }
        return context.createCGImage(finalImage, from: canvasExtent)
    }
    
    private func applyContoursEffect(original: CIImage, originalImage: UIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        let canvasSize: CGFloat = 2000
        let canvasExtent = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        
        // Leave margin for outline - scale to 90% of canvas
        let targetSize = canvasSize * 0.9
        let scale = min(targetSize / extent.width, targetSize / extent.height)
        
        let scaledOriginal = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let scaledExtent = scaledOriginal.extent
        
        // Center on canvas
        let offsetX = (canvasSize - scaledExtent.width) / 2
        let offsetY = (canvasSize - scaledExtent.height) / 2
        
        let centeredOriginal = scaledOriginal.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        let centeredMask = scaledMask.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        // Detect contours from the centered mask
        guard let cleanedMaskCGImage = context.createCGImage(centeredMask, from: canvasExtent),
              let path = try? await detectContours(from: cleanedMaskCGImage),
              let outlineImage = pathToCIImage(path, in: canvasExtent, strokeWidth: outlineThickness, color: UIColor(outlineColor)) else {
            return nil
        }
        
        let transparentBackground = CIImage.empty().cropped(to: canvasExtent)
        let maskFilter = CIFilter.blendWithMask()
        maskFilter.inputImage = centeredOriginal
        maskFilter.backgroundImage = transparentBackground
        maskFilter.maskImage = centeredMask
        
        guard let maskedPersonImage = maskFilter.outputImage else { return nil }
        
        let compositeFilter = CIFilter.sourceOverCompositing()
        compositeFilter.inputImage = maskedPersonImage
        compositeFilter.backgroundImage = outlineImage
        
        guard let finalImage = compositeFilter.outputImage else { return nil }
        return context.createCGImage(finalImage, from: canvasExtent)
    }
    
    private func applyCircleBgEffect(original: CIImage, originalImage: UIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        let canvasSize: CGFloat = 2000
        let canvasExtent = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        
        guard let detectedBox = try? await detectSaliency(from: originalImage) else { return nil }
        
        let pixelBox = CGRect(
            x: detectedBox.minX * extent.width,
            y: detectedBox.minY * extent.height,
            width: detectedBox.width * extent.width,
            height: detectedBox.height * extent.height
        )
        
        let personSize = max(pixelBox.width, pixelBox.height)
        let circleRadius = (personSize / 2) * circleRadiusMultiplier
        let circleDiameter = circleRadius * 2
        let outlineExpansion = shapeOutlineWidth * 2
        let totalVisibleDiameter = circleDiameter + outlineExpansion
        
        let targetDiameter: CGFloat = 2000
        let fillScale = targetDiameter / totalVisibleDiameter
        
        let scaledOriginal = original.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
        
        let scaledPixelBox = CGRect(
            x: pixelBox.minX * fillScale,
            y: pixelBox.minY * fillScale,
            width: pixelBox.width * fillScale,
            height: pixelBox.height * fillScale
        )
        
        let offsetX = (canvasSize / 2) - scaledPixelBox.midX
        let offsetY = (canvasSize / 2) - scaledPixelBox.midY
        
        let centeredOriginal = scaledOriginal.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        let centeredMask = scaledMask.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        let centeredBox = CGRect(
            x: (scaledPixelBox.minX + offsetX) / canvasSize,
            y: (scaledPixelBox.minY + offsetY) / canvasSize,
            width: scaledPixelBox.width / canvasSize,
            height: scaledPixelBox.height / canvasSize
        )
        
        guard let circleBackground = circleToCIImage(boundingBox: centeredBox, in: canvasExtent, color: UIColor(backgroundColor)),
              let circleMask = createCircleMask(boundingBox: centeredBox, in: canvasExtent) else {
            return nil
        }
        
        guard let circleOutline = generateShapeOutline(from: circleBackground, color: outlineColor) else { return nil }
        
        let transparentBackground = CIImage.empty().cropped(to: canvasExtent)
        
        let maskFilter1 = CIFilter.blendWithMask()
        maskFilter1.inputImage = centeredOriginal
        maskFilter1.backgroundImage = transparentBackground
        maskFilter1.maskImage = centeredMask
        
        guard let maskedPerson = maskFilter1.outputImage else { return nil }
        
        let maskFilter2 = CIFilter.blendWithMask()
        maskFilter2.inputImage = maskedPerson
        maskFilter2.backgroundImage = transparentBackground
        maskFilter2.maskImage = circleMask
        
        guard let clippedPerson = maskFilter2.outputImage else { return nil }
        
        let outlineBox = CGRect(
            x: centeredBox.minX - (shapeOutlineWidth / canvasSize),
            y: centeredBox.minY - (shapeOutlineWidth / canvasSize),
            width: centeredBox.width + (shapeOutlineWidth * 2 / canvasSize),
            height: centeredBox.height + (shapeOutlineWidth * 2 / canvasSize)
        )
        
        guard let solidOutline = circleToCIImage(boundingBox: outlineBox, in: canvasExtent, color: UIColor(outlineColor)) else { return nil }
        guard let whiteBackdrop = circleToCIImage(boundingBox: centeredBox, in: canvasExtent, color: .white) else { return nil }
        
        let backdropComposite = CIFilter.sourceOverCompositing()
        backdropComposite.inputImage = whiteBackdrop
        backdropComposite.backgroundImage = solidOutline
        
        guard let whiteLayer = backdropComposite.outputImage else { return nil }
        
        // Shrink the mask by 5% to cut a bit of the edges
        let shrinkFactor: CGFloat = 0.98
        let shrinkAmount = (1.0 - shrinkFactor) / 2.0
        let finalMaskBox = CGRect(
            x: outlineBox.minX + (outlineBox.width * shrinkAmount),
            y: outlineBox.minY + (outlineBox.height * shrinkAmount),
            width: outlineBox.width * shrinkFactor,
            height: outlineBox.height * shrinkFactor
        )
        
        if useThreeLayerEffect {
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = circleOutline
            composite1.backgroundImage = circleBackground
            
            guard let outlineOnBackground = composite1.outputImage else { return nil }
            
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = clippedPerson
            composite2.backgroundImage = outlineOnBackground
            
            guard let mainStack = composite2.outputImage else { return nil }
            
            let finalComposite = CIFilter.sourceOverCompositing()
            finalComposite.inputImage = mainStack
            finalComposite.backgroundImage = whiteLayer
            
            guard let compositedImage = finalComposite.outputImage else { return nil }
            
            // Cut the final composited image with the shrunk circular mask
            guard let finalCircleMask = createCircleMask(boundingBox: finalMaskBox, in: canvasExtent) else { return nil }
            
            let finalMaskFilter = CIFilter.blendWithMask()
            finalMaskFilter.inputImage = compositedImage
            finalMaskFilter.backgroundImage = transparentBackground
            finalMaskFilter.maskImage = finalCircleMask
            
            guard let finalImage = finalMaskFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: canvasExtent)
        } else {
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = clippedPerson
            composite1.backgroundImage = circleBackground
            
            guard let bgWithPerson = composite1.outputImage else { return nil }
            
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = bgWithPerson
            composite2.backgroundImage = circleOutline
            
            guard let mainStack = composite2.outputImage else { return nil }
            
            let finalComposite = CIFilter.sourceOverCompositing()
            finalComposite.inputImage = mainStack
            finalComposite.backgroundImage = whiteLayer
            
            guard let compositedImage = finalComposite.outputImage else { return nil }
            
            // Cut the final composited image with the shrunk circular mask
            guard let finalCircleMask = createCircleMask(boundingBox: finalMaskBox, in: canvasExtent) else { return nil }
            
            let finalMaskFilter = CIFilter.blendWithMask()
            finalMaskFilter.inputImage = compositedImage
            finalMaskFilter.backgroundImage = transparentBackground
            finalMaskFilter.maskImage = finalCircleMask
            
            guard let finalImage = finalMaskFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: canvasExtent)
        }
    }
    
    private func applyRectangleBgEffect(original: CIImage, originalImage: UIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        let canvasSize: CGFloat = 2000
        let canvasExtent = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        
        guard let detectedBox = try? await detectSaliency(from: originalImage) else { return nil }
        
        let pixelBox = CGRect(
            x: detectedBox.minX * extent.width,
            y: detectedBox.minY * extent.height,
            width: detectedBox.width * extent.width,
            height: detectedBox.height * extent.height
        )
        
        let personSize = max(pixelBox.width, pixelBox.height)
        let rectangleSize = personSize * 1.1
        let outlineExpansion = shapeOutlineWidth * 2
        let totalVisibleSize = rectangleSize + outlineExpansion
        
        let targetSize: CGFloat = 2000
        let fillScale = targetSize / totalVisibleSize
        
        let scaledOriginal = original.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
        
        let scaledPixelBox = CGRect(
            x: pixelBox.minX * fillScale,
            y: pixelBox.minY * fillScale,
            width: pixelBox.width * fillScale,
            height: pixelBox.height * fillScale
        )
        
        let offsetX = (canvasSize / 2) - scaledPixelBox.midX
        let offsetY = (canvasSize / 2) - scaledPixelBox.midY
        
        let centeredOriginal = scaledOriginal.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        let centeredMask = scaledMask.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        let centeredBox = CGRect(
            x: (scaledPixelBox.minX + offsetX) / canvasSize,
            y: (scaledPixelBox.minY + offsetY) / canvasSize,
            width: scaledPixelBox.width / canvasSize,
            height: scaledPixelBox.height / canvasSize
        )
        
        guard let rectangleBackground = roundedRectangleToCIImage(boundingBox: centeredBox, cornerRadius: cornerRadius, in: canvasExtent, color: UIColor(backgroundColor)),
              let rectangleMask = createRectangleMask(boundingBox: centeredBox, cornerRadius: cornerRadius, in: canvasExtent) else {
            return nil
        }
        
        guard let rectangleOutline = generateShapeOutline(from: rectangleBackground, color: outlineColor) else { return nil }
        
        let transparentBackground = CIImage.empty().cropped(to: canvasExtent)
        
        let maskFilter1 = CIFilter.blendWithMask()
        maskFilter1.inputImage = centeredOriginal
        maskFilter1.backgroundImage = transparentBackground
        maskFilter1.maskImage = centeredMask
        
        guard let maskedPerson = maskFilter1.outputImage else { return nil }
        
        let maskFilter2 = CIFilter.blendWithMask()
        maskFilter2.inputImage = maskedPerson
        maskFilter2.backgroundImage = transparentBackground
        maskFilter2.maskImage = rectangleMask
        
        guard let clippedPerson = maskFilter2.outputImage else { return nil }
        
        let outlineBox = CGRect(
            x: centeredBox.minX - (shapeOutlineWidth / canvasSize),
            y: centeredBox.minY - (shapeOutlineWidth / canvasSize),
            width: centeredBox.width + (shapeOutlineWidth * 2 / canvasSize),
            height: centeredBox.height + (shapeOutlineWidth * 2 / canvasSize)
        )
        
        guard let solidOutline = roundedRectangleToCIImage(boundingBox: outlineBox, cornerRadius: cornerRadius, in: canvasExtent, color: UIColor(outlineColor)) else { return nil }
        guard let whiteBackdrop = roundedRectangleToCIImage(boundingBox: centeredBox, cornerRadius: cornerRadius, in: canvasExtent, color: .white) else { return nil }
        
        let backdropComposite = CIFilter.sourceOverCompositing()
        backdropComposite.inputImage = whiteBackdrop
        backdropComposite.backgroundImage = solidOutline
        
        guard let whiteLayer = backdropComposite.outputImage else { return nil }
        
        // Shrink the mask by a fixed amount based on outline width
        let shrinkAmount = shapeOutlineWidth * 0.05 / canvasSize
        let finalMaskBox = CGRect(
            x: outlineBox.minX + shrinkAmount,
            y: outlineBox.minY + shrinkAmount,
            width: outlineBox.width - (shrinkAmount * 1.5),
            height: outlineBox.height - (shrinkAmount * 1.5)
        )
        
        // Adjust corner radius proportionally based on the shrink
        let shrinkInPixels = shapeOutlineWidth * 0.05
        let adjustedCornerRadius = max(1.0, cornerRadius - shrinkInPixels)
        
        if useThreeLayerEffect {
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = rectangleOutline
            composite1.backgroundImage = rectangleBackground
            
            guard let outlineOnBackground = composite1.outputImage else { return nil }
            
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = clippedPerson
            composite2.backgroundImage = outlineOnBackground
            
            guard let mainStack = composite2.outputImage else { return nil }
            
            let finalComposite = CIFilter.sourceOverCompositing()
            finalComposite.inputImage = mainStack
            finalComposite.backgroundImage = whiteLayer
            
            guard let compositedImage = finalComposite.outputImage else { return nil }
            
            guard let finalRectangleMask = createRectangleMask(boundingBox: finalMaskBox, cornerRadius: adjustedCornerRadius, in: canvasExtent) else { return nil }
            
            let finalMaskFilter = CIFilter.blendWithMask()
            finalMaskFilter.inputImage = compositedImage
            finalMaskFilter.backgroundImage = transparentBackground
            finalMaskFilter.maskImage = finalRectangleMask
            
            guard let finalImage = finalMaskFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: canvasExtent)
        } else {
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = clippedPerson
            composite1.backgroundImage = rectangleBackground
            
            guard let bgWithPerson = composite1.outputImage else { return nil }
            
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = bgWithPerson
            composite2.backgroundImage = rectangleOutline
            
            guard let mainStack = composite2.outputImage else { return nil }
            
            let finalComposite = CIFilter.sourceOverCompositing()
            finalComposite.inputImage = mainStack
            finalComposite.backgroundImage = whiteLayer
            
            guard let compositedImage = finalComposite.outputImage else { return nil }
            
            guard let finalRectangleMask = createRectangleMask(boundingBox: finalMaskBox, cornerRadius: adjustedCornerRadius, in: canvasExtent) else { return nil }
            
            let finalMaskFilter = CIFilter.blendWithMask()
            finalMaskFilter.inputImage = compositedImage
            finalMaskFilter.backgroundImage = transparentBackground
            finalMaskFilter.maskImage = finalRectangleMask
            
            guard let finalImage = finalMaskFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: canvasExtent)
        }
    }
    
    private func applyStandardEffect(effect: Effect, original: CIImage, mask: CIImage, extent: CGRect, context: CIContext) -> CGImage? {
        let effectImage = applyEffect(effect, to: original)
        let transparentBackground = CIImage(color: .clear).cropped(to: extent)
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = effectImage
        blendFilter.backgroundImage = transparentBackground
        blendFilter.maskImage = mask
        
        guard let outputCIImage = blendFilter.outputImage else { return nil }
        return context.createCGImage(outputCIImage, from: outputCIImage.extent)
    }
    
    private func applyEffect(_ effect: Effect, to image: CIImage) -> CIImage {
        switch effect {
        case .none, .JFA, .Countours, .CircleBg, .rectangleBg:
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
}

