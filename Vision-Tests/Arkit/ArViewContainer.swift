//
//  ArViewContainer.swift
//  Vision-Tests
//
//  Created by Jose julian Lopez on 22/10/25.
//

import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer : UIViewRepresentable {
   
    @Environment(ImageManager.self) var imageManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
            
        // configuracion del ar kit
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .vertical
        config.isLightEstimationEnabled = true
        config.frameSemantics = .personSegmentationWithDepth
        
        arView.session.run(config)
        arView.addCoaching()
        
        // Añadir gesture recognizer para tap-to-place
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(context.coordinator.handleTap)
        )
        arView.addGestureRecognizer(tapGesture)
        
        // Guardar referencia al ImageManager en el coordinator
        context.coordinator.imageManager = imageManager
        context.coordinator.arView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Actualizar la referencia al imageManager
        context.coordinator.imageManager = imageManager
    }
    
    // ✅ Crear Coordinator para manejar el tap
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var imageManager: ImageManager?
        weak var arView: ARView?
        
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = arView,
                  let imageManager = imageManager,
                  let selectedIndex = imageManager.selectedStickerIndex,
                  selectedIndex < imageManager.savedImages.count else {
                print("⚠️ No sticker selected")
                return
            }
            
            let tapLocation = recognizer.location(in: arView)
            
            let results = arView.raycast(
                from: tapLocation,
                allowing: .estimatedPlane,
                alignment: .vertical
            )
            
            guard let firstResult = results.first else {
                print("⚠️ No vertical surface detected")
                return
            }
            
            if let stickerEntity = createStickerEntity(
                from: imageManager.savedImages[selectedIndex]
            ) {
                let anchor = AnchorEntity(world: firstResult.worldTransform)
                
              
                stickerEntity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                stickerEntity.transform.rotation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                            
                anchor.addChild(stickerEntity)
                arView.scene.addAnchor(anchor)
                
                print("✅ Sticker placed on wall!")
            }
        }
        
        private func createStickerEntity(from image: UIImage) -> ModelEntity? {
            guard let cgImage = image.cgImage else {
                print("❌ Failed to get CGImage")
                return nil
            }
            
            // ✅ Crear textura
            guard let texture = try? TextureResource(
                image: cgImage,
                options: .init(semantic: .color)
            ) else {
                print("❌ Failed to create texture")
                return nil
            }
            
            // ✅ Usar PhysicallyBasedMaterial con transparencia
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.metallic = .init(floatLiteral: 0.0)
            material.roughness = .init(floatLiteral: 1.0)
            material.emissiveColor = .init(texture: .init(texture))
            material.emissiveIntensity = 0.6

            
            // ✅ La clave: activar transparencia con blending
            material.blending = .transparent(opacity: 1.0)
            
            material.opacityThreshold = 0.0
            
            let width: Float = 0.3
            let aspectRatio = Float(image.size.height / image.size.width)
            let height = width * aspectRatio
            
            let planeMesh = MeshResource.generatePlane(width: width, height: height)
            let modelEntity = ModelEntity(mesh: planeMesh, materials: [material])
            
            return modelEntity
        }
    }
}


extension ARView {
    
    func addCoaching() {
        let coachingOverlay = ARCoachingOverlayView()
    
        coachingOverlay.goal = .verticalPlane
        coachingOverlay.session = self.session
        
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.addSubview(coachingOverlay)
        
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coachingOverlay.topAnchor.constraint(equalTo: self.topAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }
}
