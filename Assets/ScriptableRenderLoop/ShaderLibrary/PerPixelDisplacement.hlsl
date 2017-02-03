// This is implementation of parallax occlusion mapping (POM)
// This function require that the caller define a callback for the height sampling name ComputePerPixelHeightDisplacement
// A PerPixelHeightDisplacementParam is used to provide all data necessary to calculate the heights to ComputePerPixelHeightDisplacement it doesn't need to be
// visible by the POM algorithm.
// This function is compatible with tiled uv.
// it return the offset to apply to the UVSet provide in PerPixelHeightDisplacementParam
// viewDirTS is view vector in texture space matching the UVSet
// ref: https://www.gamedev.net/resources/_/technical/graphics-programming-and-theory/a-closer-look-at-parallax-occlusion-mapping-r3262
float2 ParallaxOcclusionMapping(float lod, float lodThreshold, int numSteps, float3 viewDirTS, float maxHeight, PerPixelHeightDisplacementParam ppdParam)
{
    // Convention: 1.0 is top, 0.0 is bottom - POM is always inward, no extrusion
    float stepSize = 1.0 / (float)numSteps;

    // View vector is from the point to the camera, but we want to raymarch from camera to point, so reverse the sign
    // The length of viewDirTS vector determines the furthest amount of displacement:
    // float parallaxLimit = -length(viewDirTS.xy) / viewDirTS.z;
    // float2 parallaxDir = normalize(Out.viewDirTS.xy);
    // float2 parallaxMaxOffsetTS = parallaxDir * parallaxLimit;
    // Above code simplify to
    float2 parallaxMaxOffsetTS = (viewDirTS.xy / -viewDirTS.z) * maxHeight;
    float2 texOffsetPerStep = stepSize * parallaxMaxOffsetTS;

    // Do a first step before the loop to init all value correctly
    float2 texOffsetCurrent = float2(0.0, 0.0);
    float prevHeight = ComputePerPixelHeightDisplacement(texOffsetCurrent, lod, ppdParam);
    texOffsetCurrent += texOffsetPerStep;
    float currHeight = ComputePerPixelHeightDisplacement(texOffsetCurrent, lod, ppdParam);
    float rayHeight = 1.0 - stepSize; // Start at top less one sample

    // Linear search
    for (int stepIndex = 0; stepIndex < numSteps; ++stepIndex)
    {
        // Have we found a height below our ray height ? then we have an intersection
        if (currHeight > rayHeight)
            break; // end the loop

        prevHeight = currHeight;
        rayHeight -= stepSize;
        texOffsetCurrent += texOffsetPerStep;

        // Sample height map which in this case is stored in the alpha channel of the normal map:
        currHeight = ComputePerPixelHeightDisplacement(texOffsetCurrent, lod, ppdParam);
    }

    // Found below and above points, now perform line interesection (ray) with piecewise linear heightfield approximation

    // Refine the search by adding few extra intersection
#define POM_REFINE 1
#if POM_REFINE

    float pt0 = rayHeight + stepSize;
    float pt1 = rayHeight;
    float delta0 = pt0 - prevHeight;
    float delta1 = pt1 - currHeight;

    float2 offset = float2(0.0, 0.0);

    float threshold = 1.0;

    for (int i = 0; i < 5; ++i)
    {
        float t = (pt0 * delta1 - pt1 * delta0) / (delta1 - delta0);
        offset = (1 - t) * texOffsetPerStep * numSteps;

        currHeight = ComputePerPixelHeightDisplacement(offset, lod, ppdParam);

        threshold = t - currHeight;

        if (abs(threshold) <= 0.01)
            break;

        if (threshold < 0.0)
        {
            delta1 = threshold;
            pt1 = t;
        }
        else
        {
            delta0 = threshold;
            pt0 = t;
        }
    }

#else
    
    //float pt0 = rayHeight + stepSize;
    //float pt1 = rayHeight; 
    //float delta0 = pt0 - prevHeight;
    //float delta1 = pt1 - currHeight;
    //float t = (pt0 * delta1 - pt1 * delta0) / (delta1 - delta0);
    //float2 offset = (1 - t) * texOffsetPerStep * numSteps;

    // A bit more optimize
    float delta0 = currHeight - rayHeight;
    float delta1 = (rayHeight + stepSize) - prevHeight;
    float ratio = delta0 / (delta0 + delta1);
    float2 offset = texOffsetCurrent - ratio * texOffsetPerStep;

#endif

    // Fade the effect with lod (allow to avoid pop when switching to a discrete LOD mesh)
    offset *= (1.0 - saturate(lod - lodThreshold));

    return offset;
}