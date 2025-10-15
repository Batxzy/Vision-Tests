//
//  JFA.metal
//  I love testing
//
//  Created by Jose julian Lopez on 15/10/25.
//

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;


// Kernel 1: Creates the initial "seed" image from a mask.
// For every white pixel in the mask, it stores that pixel's own coordinate.
// All other pixels are zero.
extern "C" float4 seedKernel(coreimage::sampler mask) {
    float2 pos = mask.coord();
    float maskPixel = mask.sample(pos).r;

    if (maskPixel > 0.1) {
        // Store the coordinate (x, y) in the (r, g) channels.
        // Use the blue channel as a flag to indicate this is a seed pixel.
        return float4(pos.x, pos.y, 1.0, 1.0);
    } else {
        // Not a seed pixel
        return float4(0.0);
    }
}


// Kernel 2: Performs one pass of the Jump Flood Algorithm.
// It compares its own closest seed with the seeds found by its neighbors
// at a specific jump distance.
extern "C" float4 jfaPassKernel(coreimage::sampler previousPass, float jump) {
    float2 currentCoord = previousPass.coord();
    
    // Get the closest seed coordinate found so far for this pixel.
    float4 nearest = previousPass.sample(currentCoord);

    // Look at 8 neighbors at the current jump distance
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue; // Skip self

            float2 sampleCoord = currentCoord + float2(x, y) * jump;
            float4 neighborData = previousPass.sample(sampleCoord);

            // Check if the neighbor has found a seed (blue channel > 0)
            if (neighborData.b > 0.0) {
                // If we don't have a seed yet, just take the neighbor's.
                if (nearest.b == 0.0) {
                    nearest = neighborData;
                } else {
                    // If we do, check if the neighbor's seed is closer to us.
                    if (distance(currentCoord, neighborData.xy) < distance(currentCoord, nearest.xy)) {
                        nearest = neighborData;
                    }
                }
            }
        }
    }
    return nearest;
}


// Kernel 3: Renders the final outline from the Signed Distance Field (SDF).
// It calculates the distance to the stored seed coordinate and draws if it's
// within the specified thickness.
// --- THIS IS THE CORRECTED LINE ---
extern "C" float4 sdfToOutlineKernel(coreimage::sampler sdf, float thickness, float softness, float4 color) {
    float2 currentCoord = sdf.coord();
    float4 storedData = sdf.sample(currentCoord);
    
    // This is the true distance to the nearest edge.
    float dist = distance(currentCoord, storedData.xy);
    
    // Use smoothstep for anti-aliasing to get a soft, clean edge.
    float alpha = smoothstep(thickness, thickness - softness, dist);
    
    return float4(color.rgb, color.a * alpha);
}
