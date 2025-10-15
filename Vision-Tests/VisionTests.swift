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
    var backgroundColor: UIColor = .white
    
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
    
    private func pathToCIImage(_ path: CGPath, in extent: CGRect, strokeWidth: CGFloat) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
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
    
    private func circleToCIImage(boundingBox: CGRect, in extent: CGRect) -> CIImage? {
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
            
            // Only fill with solid color, no stroke
            context.cgContext.setFillColor(backgroundColor.cgColor)
            context.cgContext.fillEllipse(in: rect)
        }
        
        return CIImage(image: image)
    }
    
    private func roundedRectangleToCIImage(boundingBox: CGRect, cornerRadius: CGFloat, in extent: CGRect) -> CIImage? {
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
            
            // Only fill with solid color, no stroke
            context.cgContext.setFillColor(backgroundColor.cgColor)
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
    
    private func generateJFAOutline(from mask: CIImage) -> CIImage? {
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = mask
        morphology.radius = Float(outlineThickness)
        
        guard let edgeImage = morphology.outputImage else { return nil }
        
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = edgeImage
        blur.radius = 3.0
        
        guard let blurredEdge = blur.outputImage else { return nil }
        
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = blurredEdge
        colorMatrix.rVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.gVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.bVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    }
    
    private func generateShapeOutline(from shape: CIImage) -> CIImage? {
        let morphology = CIFilter.morphologyGradient()
        morphology.inputImage = shape
        morphology.radius = Float(shapeOutlineWidth)
        
        guard let edgeImage = morphology.outputImage else { return nil }
        
        // Make it black
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = edgeImage
        colorMatrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        colorMatrix.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        
        return colorMatrix.outputImage
    }
    
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
        guard let outlineImage = generateJFAOutline(from: mask) else { return nil }
        
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
              let outlineImage = pathToCIImage(path, in: extent, strokeWidth: outlineThickness) else {
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
              let circleBackground = circleToCIImage(boundingBox: boundingBox, in: extent),
              let circleMask = createCircleMask(boundingBox: boundingBox, in: extent) else {
            return nil
        }
        
        // Generate outline from circle mask
        guard let circleOutline = generateShapeOutline(from: circleBackground) else { return nil }
        
        // Mask person from original image
        let transparentBackground = CIImage.empty().cropped(to: extent)
        let maskFilter1 = CIFilter.blendWithMask()
        maskFilter1.inputImage = original
        maskFilter1.backgroundImage = transparentBackground
        maskFilter1.maskImage = mask
        
        guard let maskedPerson = maskFilter1.outputImage else { return nil }
        
        // Clip person to circle shape
        let maskFilter2 = CIFilter.blendWithMask()
        maskFilter2.inputImage = maskedPerson
        maskFilter2.backgroundImage = transparentBackground
        maskFilter2.maskImage = circleMask
        
        guard let clippedPerson = maskFilter2.outputImage else { return nil }
        
        // Composite: background -> outline -> person
        let composite1 = CIFilter.sourceOverCompositing()
        composite1.inputImage = circleOutline
        composite1.backgroundImage = circleBackground
        
        guard let bgWithOutline = composite1.outputImage else { return nil }
        
        let composite2 = CIFilter.sourceOverCompositing()
        composite2.inputImage = clippedPerson
        composite2.backgroundImage = bgWithOutline
        
        guard let finalImage = composite2.outputImage else { return nil }
        return context.createCGImage(finalImage, from: extent)
    }

    private func applyRectangleBgEffect(original: CIImage, originalImage: UIImage, mask: CIImage, extent: CGRect, context: CIContext) async -> CGImage? {
        guard let boundingBox = try? await detectHumanRectangles(from: originalImage),
              let rectangleBackground = roundedRectangleToCIImage(boundingBox: boundingBox, cornerRadius: cornerRadius, in: extent),
              let rectangleMask = createRectangleMask(boundingBox: boundingBox, cornerRadius: cornerRadius, in: extent) else {
            return nil
        }
        
        // Generate outline from rectangle mask
        guard let rectangleOutline = generateShapeOutline(from: rectangleBackground) else { return nil }
        
        // Mask person from original image
        let transparentBackground = CIImage.empty().cropped(to: extent)
        let maskFilter1 = CIFilter.blendWithMask()
        maskFilter1.inputImage = original
        maskFilter1.backgroundImage = transparentBackground
        maskFilter1.maskImage = mask
        
        guard let maskedPerson = maskFilter1.outputImage else { return nil }
        
        // Clip person to rectangle shape
        let maskFilter2 = CIFilter.blendWithMask()
        maskFilter2.inputImage = maskedPerson
        maskFilter2.backgroundImage = transparentBackground
        maskFilter2.maskImage = rectangleMask
        
        guard let clippedPerson = maskFilter2.outputImage else { return nil }
        
        // Composite: background -> outline -> person
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
            
            if pipeline.currentEffect == .CircleBg {
                VStack(spacing: 12) {
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
                        Slider(value: $pipeline.shapeOutlineWidth, in: 0...20) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .tint(.blue)
            }
            
            if pipeline.currentEffect == .rectangleBg {
                VStack(spacing: 12) {
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
                        Slider(value: $pipeline.shapeOutlineWidth, in: 0...20) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
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
                if let image = UIImage(named: "Turing") {
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
