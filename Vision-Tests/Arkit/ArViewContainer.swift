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
   

    //el wey que va tener y cargar mis stickers
    @Environment(ImageManager.self) var imageManager

    //creo una piche view ARVIew nada mas, el rendering lo va a hacer reality kit en si
    
    //pero asi abro la sesion para que el iphone obtenga datos
    
    //esto crea una view que swift iu puede leer
    func makeUIView(context: Context) -> ARView {
        
        //instanseo y creo de la clase arview una que no tiene medidas aun
        let arView = ARView(frame: .zero)
            
        
            // configuracion del ar kit
            let config = ARWorldTrackingConfiguration()
        
            config.planeDetection = .vertical
        
            config.isLightEstimationEnabled = true
        
            config.sceneReconstruction = .mesh
               
            config.frameSemantics = .personSegmentationWithDepth
        
        
            //esto crea la session de ar kit en si
            arView.session.run(config)
        
           return ARView()
       }
    
    
    //la funcion que añade o le quita cosas a nuestra escena // solo tiene una perrra escena por view
    
    //si quiero tener una entidad dentro del mundo, esta tiene que nacer de un aentidad de anchor
    
    
    func updateUIView(_ uiView: ARView, context: Context) {
            print("\n🔄 updateUIView called")
            
            // Limpiar escena
            uiView.scene.anchors.removeAll()
            print("🧹 Cleared previous anchors")
            
            // Validar que hay imagen seleccionada
            guard let selectedIndex = imageManager.selectedStickerIndex,
                  selectedIndex < imageManager.savedImages.count else {
                print("⚠️ No sticker selected or invalid index")
                return
            }
            
            print("📸 Creating sticker for index: \(selectedIndex)")
            
            // Crear el sticker
            if let stickerEntity = createStickerEntity(from: imageManager.savedImages[selectedIndex]) {
                let anchor = AnchorEntity(plane: .vertical)
                anchor.addChild(stickerEntity)
                uiView.scene.addAnchor(anchor)
                print("✅ Sticker added to scene successfully!\n")
            } else {
                print("❌ Failed to create sticker entity\n")
            }
        }
        
        // Método helper separado para crear el sticker
        private func createStickerEntity(from image: UIImage) -> ModelEntity? {
            print("  🖼️  Image size: \(Int(image.size.width))x\(Int(image.size.height))")
            
            // Obtener CGImage
            guard let cgImage = image.cgImage else {
                print("  ❌ Failed to get CGImage")
                return nil
            }
            print("  ✅ CGImage obtained")
            
            // Crear textura
            guard let texture = try? TextureResource(
                image: cgImage,
                options: .init(semantic: .color)
            ) else {
                print("  ❌ Failed to create TextureResource")
                return nil
            }
            print("  ✅ TextureResource created")
            
            // Crear material
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            print("  ✅ Material created")
            
            // Calcular dimensiones con aspect ratio
            let width: Float = 0.3
            let aspectRatio = Float(image.size.height / image.size.width)
            let height = width * aspectRatio
            print("  📐 Plane dimensions: \(width)m x \(height)m (aspect: \(String(format: "%.2f", aspectRatio)))")
            
            // Crear plano y entity
            let planeMesh = MeshResource.generatePlane(width: width, height: height)
            let modelEntity = ModelEntity(mesh: planeMesh, materials: [material])
            
            print("  ✅ ModelEntity created successfully")
            return modelEntity
        }
    }
