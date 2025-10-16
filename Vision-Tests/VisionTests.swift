import SwiftUI
import VisionKit
import Vision
import CoreImage.CIFilterBuiltins

@Observable
class EffectsPipeline {
    var inputImage: UIImage?
    var outputImage: UIImage?
    var isProcessing = false
    var currentEffect: Effect = .none
    
    var outlineThickness: Double = 15.0
    var cornerRadius: Double = 20.0
    var circleRadiusMultiplier: Double = 1.1
    var shapeOutlineWidth: Double = 5.0
    var backgroundColor: Color = .white
    var outlineColor: Color = .black
    var useThreeLayerEffect: Bool = false
    
    enum Effect: String, CaseIterable, Identifiable {
        case none = "None"
        case photoEffectProcess = "Process"
        case JFA = "JumpFlood"
        case Countours = "contours"
        case CircleBg = "circle background"
        case rectangleBg = "rectangle background"
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
        guard let cgImage = image.cgImage else { return nil }
        
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let results = request.results, !results.isEmpty else { return nil }
        
        var unionBox = results[0].boundingBox
        for i in 1..<results.count {
            unionBox = unionBox.union(results[i].boundingBox)
        }
        
        return unionBox
    }
    
    private func detectSaliency(from image: UIImage) async throws -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let saliency = request.results?.first,
              let salientObjects = saliency.salientObjects, !salientObjects.isEmpty else {
            return nil
        }
        
        var unionBox = salientObjects[0].boundingBox
        for i in 1..<salientObjects.count {
            unionBox = unionBox.union(salientObjects[i].boundingBox)
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
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            
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
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            
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
    
    
    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) async -> CGImage? {
        guard let ciOriginalImage = CIImage(image: originalImage) else { return nil }
        let originalExtent = ciOriginalImage.extent
        guard let ciMaskImage = cleanSegmentationMask(maskCGImage, targetSize: originalExtent.size) else { return nil }
        let context = CIContext()
        
        switch effect {
        case .JFA:
            return await applyJFAEffect(original: ciOriginalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        case .Countours:
            return await applyContoursEffect(original: ciOriginalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        case .CircleBg:
            return await applyCircleBgEffect(original: ciOriginalImage, originalImage: originalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        case .rectangleBg:
            return await applyRectangleBgEffect(original: ciOriginalImage, originalImage: originalImage, mask: ciMaskImage, extent: originalExtent, context: context)
            
        default:
            return applyStandardEffect(effect: effect, original: ciOriginalImage, mask: ciMaskImage, extent: originalExtent, context: context)
        }
    }
    
    private func applyJFAEffect(original: CIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        guard let outlineImage = generateJFAOutline(from: mask, color: outlineColor) else { return nil }
        
        let transparentBackground = CIImage.empty().cropped(to: extent)
        let maskFilter = CIFilter.blendWithMask()
        maskFilter.inputImage = original
        maskFilter.backgroundImage = transparentBackground
        maskFilter.maskImage = mask
        
        guard let maskedPersonImage = maskFilter.outputImage else { return nil }
        
        let compositeFilter = CIFilter.sourceOverCompositing()
        compositeFilter.inputImage = maskedPersonImage
        compositeFilter.backgroundImage = outlineImage
        
        guard let finalImage = compositeFilter.outputImage else { return nil }
        return context.createCGImage(finalImage, from: extent)
    }
    
    private func applyContoursEffect(original: CIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        guard let cleanedMaskCGImage = context.createCGImage(mask, from: extent),
              let path = try? await detectContours(from: cleanedMaskCGImage),
              let outlineImage = pathToCIImage(path, in: extent, strokeWidth: outlineThickness, color: UIColor(outlineColor)) else {
            return nil
        }
        
        let transparentBackground = CIImage.empty().cropped(to: extent)
        let maskFilter = CIFilter.blendWithMask()
        maskFilter.inputImage = original
        maskFilter.backgroundImage = transparentBackground
        maskFilter.maskImage = mask
        
        guard let maskedPersonImage = maskFilter.outputImage else { return nil }
        
        let compositeFilter = CIFilter.sourceOverCompositing()
        compositeFilter.inputImage = maskedPersonImage
        compositeFilter.backgroundImage = outlineImage
        
        guard let finalImage = compositeFilter.outputImage else { return nil }
        return context.createCGImage(finalImage, from: extent)
    }

    
    private func applyCircleBgEffect(original: CIImage, originalImage: UIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        guard let boundingBox = try? await detectSaliency(from: originalImage),
              let circleBackground = circleToCIImage(boundingBox: boundingBox, in: extent, color: UIColor(backgroundColor)),
              let circleMask = createCircleMask(boundingBox: boundingBox, in: extent) else {
            return nil
        }
        
        guard let circleOutline = generateShapeOutline(from: circleBackground, color: outlineColor) else { return nil }
        
        let transparentBackground = CIImage.empty().cropped(to: extent)
        let maskFilter1 = CIFilter.blendWithMask()
        maskFilter1.inputImage = original
        maskFilter1.backgroundImage = transparentBackground
        maskFilter1.maskImage = mask
        
        guard let maskedPerson = maskFilter1.outputImage else { return nil }
        
        let maskFilter2 = CIFilter.blendWithMask()
        maskFilter2.inputImage = maskedPerson
        maskFilter2.backgroundImage = transparentBackground
        maskFilter2.maskImage = circleMask
        
        guard let clippedPerson = maskFilter2.outputImage else { return nil }
        
        if useThreeLayerEffect {
            // --- CORRECTED LOGIC FOR "OUTLINE ON TOP" ---
            // 1. Place the outline ON TOP of the background circle.
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = circleOutline
            composite1.backgroundImage = circleBackground
            
            guard let outlineOnBackground = composite1.outputImage else { return nil }
            
            // 2. Place the person ON TOP of the combined outline/background image.
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = clippedPerson
            composite2.backgroundImage = outlineOnBackground
            
            guard let finalImage = composite2.outputImage else { return nil }
            return context.createCGImage(finalImage, from: extent)
        } else {
            // This is the logic for when the outline is behind the background.
            // It remains the same as the previous fix.
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = clippedPerson
            composite1.backgroundImage = circleBackground
            
            guard let bgWithPerson = composite1.outputImage else { return nil }
            
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = bgWithPerson
            composite2.backgroundImage = circleOutline
            
            guard let finalImage = composite2.outputImage else { return nil }
            return context.createCGImage(finalImage, from: extent)
        }
    }

    
    private func applyRectangleBgEffect(original: CIImage, originalImage: UIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        guard let boundingBox = try? await detectHumanRectangles(from: originalImage),
              let rectangleBackground = roundedRectangleToCIImage(boundingBox: boundingBox, cornerRadius: cornerRadius, in: extent, color: UIColor(backgroundColor)),
              let rectangleMask = createRectangleMask(boundingBox: boundingBox, cornerRadius: cornerRadius, in: extent) else {
            return nil
        }
        
        guard let rectangleOutline = generateShapeOutline(from: rectangleBackground, color: outlineColor) else { return nil }
        
        let transparentBackground = CIImage.empty().cropped(to: extent)
        let maskFilter1 = CIFilter.blendWithMask()
        maskFilter1.inputImage = original
        maskFilter1.backgroundImage = transparentBackground
        maskFilter1.maskImage = mask
        
        guard let maskedPerson = maskFilter1.outputImage else { return nil }
        
        let maskFilter2 = CIFilter.blendWithMask()
        maskFilter2.inputImage = maskedPerson
        maskFilter2.backgroundImage = transparentBackground
        maskFilter2.maskImage = rectangleMask
        
        guard let clippedPerson = maskFilter2.outputImage else { return nil }
        
        if useThreeLayerEffect {
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = clippedPerson
            composite1.backgroundImage = rectangleBackground
            
            guard let bgWithPerson = composite1.outputImage else { return nil }
            
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = rectangleOutline
            composite2.backgroundImage = bgWithPerson
            
            guard let finalImage = composite2.outputImage else { return nil }
            return context.createCGImage(finalImage, from: extent)
        } else {
            let composite1 = CIFilter.sourceOverCompositing()
            composite1.inputImage = rectangleOutline
            composite1.backgroundImage = rectangleBackground
            
            guard let bgWithOutline = composite1.outputImage else { return nil }
            
            let composite2 = CIFilter.sourceOverCompositing()
            composite2.inputImage = clippedPerson
            composite2.backgroundImage = bgWithOutline
            
            guard let finalImage = composite2.outputImage else { return nil }
            return context.createCGImage(finalImage, from: extent)
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
    
    func changeEffect(to effect: Effect) async {
        currentEffect = effect
        await processImage()
    }
}

struct VisionTests: View {
    @State private var pipeline = EffectsPipeline()
    
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
