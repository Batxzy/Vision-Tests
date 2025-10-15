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
    var contourThickness: Double = 10.0
    var pathSimplification: Double = 0.01
    
    enum Effect: String, CaseIterable, Identifiable {
        case none = "None"
        case photoEffectProcess = "Process"
        case JFA = "JumpFlood"
        case Countours = "Contours"
        case CircleBackground = "Circle BG"
        case RectangleBackground = "Rect BG"
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
    
    private func detectContours(from ciMask: CIImage, epsilon: Float) async throws -> ContoursObservation.Contour? {
        var request = DetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true
        
        let observation = try await request.perform(on: ciMask, orientation: .up)
        
        guard let topContour = observation.topLevelContours.first else { return nil }
        
        let simplified = try topContour.polygonApproximation(epsilon: epsilon)
        
        return simplified
    }
    
    private func contourToPath(_ contour: ContoursObservation.Contour, in extent: CGRect) -> CGPath {
        let path = CGMutablePath()
        
        let pointCount = contour.pointCount
        if pointCount == 0 { return path }
        
        let points = contour.normalizedPoints
        
        let firstPoint = CGPoint(
            x: CGFloat(points[0].x) * extent.width,
            y: (1 - CGFloat(points[0].y)) * extent.height
        )
        path.move(to: firstPoint)
        
        for i in 1..<pointCount {
            let point = CGPoint(
                x: CGFloat(points[i].x) * extent.width,
                y: (1 - CGFloat(points[i].y)) * extent.height
            )
            path.addLine(to: point)
        }
        
        path.closeSubpath()
        return path
    }
    
    private func createBoundingCircle(from ciMask: CIImage, in extent: CGRect) async throws -> VNCircle {
        var request = DetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true
        
        let observation = try await request.perform(on: ciMask, orientation: .up)
        
        if let topContour = observation.topLevelContours.first {
            let path = topContour.normalizedPath
            let boundingBox = path.boundingBox
            
            let center = VNPoint(
                x: boundingBox.midX,
                y: boundingBox.midY
            )
            
            let radius = max(boundingBox.width, boundingBox.height) / 2 * 1.1
            
            return VNCircle(center: center, radius: radius)
        }
        
        return VNCircle(center: VNPoint(x: 0.5, y: 0.5), radius: 0.5)
    }
    
    private func createBoundingRectangle(from ciMask: CIImage, in extent: CGRect) async throws -> CGRect {
        var request = DetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true
        
        let observation = try await request.perform(on: ciMask, orientation: .up)
        
        if let topContour = observation.topLevelContours.first {
            let path = topContour.normalizedPath
            let boundingBox = path.boundingBox
            
            let padding: CGFloat = 0.05
            return CGRect(
                x: max(0, boundingBox.minX - padding),
                y: max(0, boundingBox.minY - padding),
                width: min(1.0, boundingBox.width + padding * 2),
                height: min(1.0, boundingBox.height + padding * 2)
            )
        }
        
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    
    private func circleToCIImage(_ circle: VNCircle, in extent: CGRect) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            let center = CGPoint(
                x: CGFloat(circle.center.x) * extent.width,
                y: (1 - CGFloat(circle.center.y)) * extent.height
            )
            let radius = circle.radius * min(extent.width, extent.height)
            
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
    
    private func rectangleToCIImage(_ normalizedRect: CGRect, in extent: CGRect) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            let rect = CGRect(
                x: normalizedRect.minX * extent.width,
                y: (1 - normalizedRect.maxY) * extent.height,
                width: normalizedRect.width * extent.width,
                height: normalizedRect.height * extent.height
            )
            
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(rect)
        }
        
        return CIImage(image: image)
    }
    
    private func pathToCIImage(_ path: CGPath, strokeWidth: CGFloat, in extent: CGRect) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: extent.size, format: format)
        
        let image = renderer.image { context in
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(strokeWidth)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            
            context.cgContext.addPath(path)
            context.cgContext.strokePath()
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
    
    private func applyEffectWithMask(originalImage: UIImage, maskCGImage: CGImage, effect: Effect) async -> CGImage? {
        guard let ciOriginalImage = CIImage(image: originalImage) else { return nil }
        
        let originalExtent = ciOriginalImage.extent
        
        guard let ciMaskImage = cleanSegmentationMask(maskCGImage, targetSize: originalExtent.size) else {
            return nil
        }
        
        let context = CIContext()
        
        if effect == .JFA {
            guard let outlineImage = generateJFAOutline(from: ciMaskImage) else { return nil }
            
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
            
        } else if effect == .Countours {
            guard let contour = try? await detectContours(from: ciMaskImage, epsilon: Float(self.pathSimplification)) else {
                return nil
            }
            
            let path = contourToPath(contour, in: originalExtent)
            
            guard let outlineImage = pathToCIImage(path, strokeWidth: self.contourThickness, in: originalExtent) else {
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
            
        } else if effect == .CircleBackground {
            guard let circle = try? await createBoundingCircle(from: ciMaskImage, in: originalExtent),
                  let circleImage = circleToCIImage(circle, in: originalExtent) else {
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
            compositeFilter.backgroundImage = circleImage
            
            guard let finalImage = compositeFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: originalExtent)
            
        } else if effect == .RectangleBackground {
            guard let normalizedRect = try? await createBoundingRectangle(from: ciMaskImage, in: originalExtent),
                  let rectangleImage = rectangleToCIImage(normalizedRect, in: originalExtent) else {
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
            compositeFilter.backgroundImage = rectangleImage
            
            guard let finalImage = compositeFilter.outputImage else { return nil }
            return context.createCGImage(finalImage, from: originalExtent)
        }
        
        let effectImage = applyEffect(effect, to: ciOriginalImage)
        let transparentBackground = CIImage(color: .clear).cropped(to: originalExtent)
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = effectImage
        blendFilter.backgroundImage = transparentBackground
        blendFilter.maskImage = ciMaskImage
        
        guard let outputCIImage = blendFilter.outputImage else { return nil }
        return context.createCGImage(outputCIImage, from: outputCIImage.extent)
    }
    
    private func applyEffect(_ effect: Effect, to image: CIImage) -> CIImage {
        switch effect {
        case .none, .JFA, .Countours, .CircleBackground, .RectangleBackground:
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
            
            if pipeline.currentEffect == .Countours {
                VStack(spacing: 12) {
                    VStack {
                        Text("Contour Thickness: \(Int(pipeline.contourThickness))")
                        Slider(value: $pipeline.contourThickness, in: 1...30) { isEditing in
                            if !isEditing {
                                Task { await pipeline.processImage() }
                            }
                        }
                    }
                    
                    VStack {
                        Text("Path Simplification: \(String(format: "%.3f", pipeline.pathSimplification))")
                        Slider(value: $pipeline.pathSimplification, in: 0.001...0.05) { isEditing in
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
