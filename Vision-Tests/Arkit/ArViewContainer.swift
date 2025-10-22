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
        
        let anchorEntity = AnchorEntity(plane: .vertical)
        
    
        // Validar índice
           guard let selectedIndex = imageManager.selectedStickerIndex,
                 selectedIndex < imageManager.savedImages.count else { return }
           
           // Obtener imagen (ya no es opcional porque validamos el índice)
           let stickerImage = imageManager.savedImages[selectedIndex]
           
           // Obtener CGImage
           guard let cgImage = stickerImage.cgImage else { return }
           
           // Crear textura y material
        guard let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return }
           
           var material = UnlitMaterial()
           material.color = .init(tint: .white, texture: .init(texture))
           
           // Crear plano con aspect ratio correcto
           let width: Float = 0.3
           let aspectRatio = Float(stickerImage.size.height / stickerImage.size.width)
           let planeMesh = MeshResource.generatePlane(width: width, height: width * aspectRatio)
        
        let stickerEntity = ModelEntity(mesh: planeMesh, materials: [material])
        
            anchorEntity.addChild(stickerEntity)
            uiView.scene.addAnchor(anchorEntity)
        
    }
    
        
}
