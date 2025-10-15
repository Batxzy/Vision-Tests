#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

// Simple outline kernel - checks distance to mask edge directly
extern "C" float4 sdfToOutlineKernel(coreimage::sampler originalMask,
                                     float thickness,
                                     float borderWidth,
                                     float softness,
                                     float4 color)
{
    float2 currentCoord = originalMask.coord();
    float maskValue = originalMask.sample(currentCoord).r;
    
    // Only process pixels OUTSIDE the mask
    if (maskValue < 0.5) {
        // Search in a radius around this pixel for the nearest edge
        float minDist = 999999.0;
        int searchRadius = int(thickness) + 5;
        
        for (int dy = -searchRadius; dy <= searchRadius; ++dy) {
            for (int dx = -searchRadius; dx <= searchRadius; ++dx) {
                float2 samplePos = currentCoord + float2(dx, dy);
                float sampleMask = originalMask.sample(samplePos).r;
                
                // Found edge pixel (transition from inside to outside)
                if (sampleMask > 0.5) {
                    float dist = length(float2(dx, dy));
                    minDist = min(minDist, dist);
                }
            }
        }
        
        // Draw outline if within thickness
        if (minDist <= thickness) {
            float alpha = 1.0 - (minDist / thickness);
            return float4(1.0, 1.0, 1.0, alpha);
        }
    }
    
    return float4(0.0);
}
