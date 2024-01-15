#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

TEXTURE2D(_WeatherTex);  //r density, b type of clouds(0~1)
SAMPLER(sampler_WeatherTex);

//Sampling Cloud info
struct SamplingInfo
{
    float3 position;                // sampling position
    float weatherTexTiling;         
    float2 weatherTexOffset;        
    float densityMultiplier;        //zoom in and zoom out
    float cloudDensityAdjust;       
    float3 windDirection;           
    float windSpeed;                
    float2 cloudHeightMinMax;       
    float cloudOffsetLower;         // offset of the bottom cloud
    float cloudOffsetUpper;         // offset of the Upper cloud
    float feather;                  // feather the cloud
    float3 sphereCenter;            // the center position of the earth
    float earthRadius;              
};

//Return Info(density only)
struct CloudInfo
{
    float density;          
};

//When a ray intersects with a sphere, return the nearest distance to the sphere and the distance traversed through the sphere.
float2 RaySphereDst(float3 sphereCenter, float sphereRadius, float3 pos, float3 rayDir)
{
    float3 oc = pos - sphereCenter;
    float b = dot(rayDir, oc);
    float c = dot(oc, oc) - sphereRadius * sphereRadius;
    float t = b * b - c;
    
    float delta = sqrt(max(t, 0));
    float dstToSphere = max(-b - delta, 0);
    float dstInSphere = max(-b + delta - dstToSphere, 0);
    return float2(dstToSphere, dstInSphere);
}


float2 RayCloudLayerDst(float3 sphereCenter, float earthRadius, float heightMin, float heightMax, float3 pos, float3 rayDir, bool isShape = true)
{
    float2 cloudDstMin = RaySphereDst(sphereCenter, heightMin + earthRadius, pos, rayDir);
    float2 cloudDstMax = RaySphereDst(sphereCenter, heightMax + earthRadius, pos, rayDir);
    
    // the closest distance from laser to the cloud
    float dstToCloudLayer = 0;
    // the farthest distance from laser to the cloud
    float dstInCloudLayer = 0;
    
    if (isShape)
    {
        // on the ground
        if (pos.y <= heightMin)
        {
            float3 startPos = pos + rayDir * cloudDstMin.y;
            // if the start position is over the ground
            if (startPos.y >= 0)
            {
                dstToCloudLayer = cloudDstMin.y;
                dstInCloudLayer = cloudDstMax.y - cloudDstMin.y;
            }
            return float2(dstToCloudLayer, dstInCloudLayer);
        }
        
        // in the cloud
        if (pos.y > heightMin && pos.y <= heightMax)
        {
            dstToCloudLayer = 0;
            dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x: cloudDstMax.y;
            return float2(dstToCloudLayer, dstInCloudLayer);
        }
        
        // above the cloud
        dstToCloudLayer = cloudDstMax.x;
        dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x - dstToCloudLayer: cloudDstMax.y;
    }
    else//sampling point must inside the cloud when ray marching
    {
        dstToCloudLayer = 0;
        dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x: cloudDstMax.y;
    }
    
    return float2(dstToCloudLayer, dstInCloudLayer);
}

// get the ratio of height
float GetHeightFraction(float3 sphereCenter, float earthRadius, float3 pos, float height_min, float height_max)
{
    float height = length(pos - sphereCenter) - earthRadius;
    return(height - height_min) / (height_max - height_min);
}

//remap
float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + ((original_value - original_min) / (original_max - original_min)) * (new_max - new_min);
}

// get the density from different type of cloud
float GetCloudTypeDensity(float heightFraction, float cloud_min, float cloud_max, float feather)
{
    //multiply 0.5 at the bottom of the cloud
    return saturate(Remap(heightFraction, cloud_min, cloud_min + feather * 0.5, 0, 1)) * saturate(Remap(heightFraction, cloud_max - feather, cloud_max, 1, 0));
}


float Interpolation3(float value1, float value2, float value3, float x, float offset = 0.5)
{
    offset = clamp(offset, 0.0001, 0.9999);
    return lerp(lerp(value1, value2, min(x, offset) / offset), value3, max(0, x - offset) / (1.0 - offset));
}

//sample the density of cloud
CloudInfo SampleCloudDensity_No3DTex(SamplingInfo dsi)
{
    CloudInfo o;
    
    float heightFraction = GetHeightFraction(dsi.sphereCenter, dsi.earthRadius, dsi.position, dsi.cloudHeightMinMax.x, dsi.cloudHeightMinMax.y);
    
    // add effect of wind
    float3 wind = dsi.windDirection * dsi.windSpeed * _Time.y;
    float3 position = dsi.position + wind * 100;
    
    //sample the weather texture, with r density, b height of the bottom cloud, a height of the top cloud
    float2 weatherTexUV = dsi.position.xz * dsi.weatherTexTiling;
    float4 weatherData = SAMPLE_TEXTURE2D_LOD(_WeatherTex, sampler_WeatherTex, weatherTexUV * 0.000001 + dsi.weatherTexOffset +wind.xz * 0.01, 0);
    weatherData.r = Interpolation3(0, weatherData.r, 1, dsi.cloudDensityAdjust);
    weatherData.b = saturate(weatherData.b + dsi.cloudOffsetLower);
    weatherData.a = saturate(weatherData.a + dsi.cloudOffsetUpper);
    float lowerLayerHeight = Interpolation3(weatherData.b, weatherData.b, 0, dsi.cloudDensityAdjust);// get bottom cloud height
    float upperLayerHeight = Interpolation3(weatherData.a, weatherData.a, 1, dsi.cloudDensityAdjust);// get top cloud height
    
    if (weatherData.r <= 0)
    {
        o.density = 0;
        return o;
    }
    
    // calculate the density
    float cloudDensity = GetCloudTypeDensity(heightFraction, min(lowerLayerHeight, upperLayerHeight), max(lowerLayerHeight, upperLayerHeight), dsi.feather);
    if (cloudDensity <= 0)
    {
        o.density = 0;
        return o;
    }
    
    cloudDensity *= weatherData.r;
    
    o.density = cloudDensity * dsi.densityMultiplier * 0.01;
    
    return o;
}


