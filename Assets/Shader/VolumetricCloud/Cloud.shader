Shader "Scarecrow/Cloud"
{
    Properties
    {
        [HDR]_BaseColor ("Base Color", color) = (1, 1, 1, 1)
        [NoScaleOffset]_CloudTex ("111", 2D) = "white" { }

        [NoScaleOffset]_WeatherTex ("Weather Texture", 2D) = "white" { }
        [HideInInspector]_WeatherTexTiling ("Weather Texture Tiling", Range(0.1, 30)) = 1
        _WeatherTexOffset ("Weather Texture Offset", vector) = (0, 0, 0, 0)
        
        [Range]_CloudHeightRange ("Cloud Height Min/Max", vector) = (1500, 4000, 0, 8000)
        _CloudCover ("CloudCoverRate", Range(0, 1)) = 0.5
        _CloudOffsetLower ("Cloud Offset Lower", Range(-1, 1)) = 0
        _CloudOffsetUpper ("Cloud Offset Upper", Range(-1, 1)) = 0
        _CloudFeather ("Cloud Feature", Range(0, 1)) = 0.2
        
        
        _ShapeMarchLength ("Per Shapemarch Length", Range(0.001, 800)) = 300
        _ShapeMarchMax ("Shapemarch Max Count", Range(3, 100)) = 30
        
        _WindDirecton ("Wind Direction", vector) = (1, 0, 0, 0)
        _WindSpeed ("Wind Speed", Range(0, 5)) = 1
        _DensityScale ("Density Scale", Range(0, 2)) = 1
        
        [HideInInspector]_MainTex ("Texture", 2D) = "white" { }
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "CloudHelp.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
        
        half4 _BaseColor;

        float _WeatherTexTiling;
        float2 _WeatherTexOffset;
        float4 _CloudHeightRange;
        float _CloudCover;
        float _CloudOffsetLower;
        float _CloudOffsetUpper;
        float _CloudFeather;
        
        float _ShapeMarchLength;
        int _ShapeMarchMax;
        
        float3 _WindDirecton;
        float _WindSpeed;
        float _DensityScale;
        
        CBUFFER_END
        
        ENDHLSL
        
        Pass
        {
            // Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
            

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D(_CloudTex);
            SAMPLER(sampler_CloudTex);
            
            struct appdata
            {
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };
            
            struct v2f
            {
                float4 vertex: SV_POSITION;
                float2 uv: TEXCOORD0;
                float3 viewDir: TEXCOORD1;
            };
            
            
            v2f vert(appdata v)
            {
                v2f o;
                
                VertexPositionInputs vertexPos = GetVertexPositionInputs(v.vertex.xyz);
                o.vertex = vertexPos.positionCS;
                o.uv = v.uv;
                
                float3 viewDir = mul(unity_CameraInvProjection, float4(v.uv * 2.0 - 1.0, 0, -1)).xyz;
                o.viewDir = mul(unity_CameraToWorld, float4(viewDir, 0)).xyz;
                
                return o;
            }
            
            half4 frag(v2f i): SV_Target
            {
                half4 backColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);      
                
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv).x;
                float dstToObj = LinearEyeDepth(depth, _ZBufferParams);
                
                //获取灯光信息
                Light mainLight = GetMainLight();
                
                float3 viewDir = normalize(i.viewDir);
                float3 lightDir = normalize(mainLight.direction);
                float3 cameraPos = GetCameraPositionWS();
                
                //The radius of the Earth varies from 6357Km to 6378Km.    
                float earthRadius = 6300000;
                //The coordinates of the Earth's center ensure that horizontal walking will never leave the Earth, 
                //with an altitude of 0 representing the surface of the Earth.
                float3 sphereCenter = float3(cameraPos.x, -earthRadius, cameraPos.z);
                
                //Calculate the starting and ending positions of the ray march step.
                float2 dstCloud = RayCloudLayerDst(sphereCenter, earthRadius, _CloudHeightRange.x, _CloudHeightRange.y, cameraPos, viewDir);
                // #endif
                float dstToCloud = dstCloud.x;
                float dstInCloud = dstCloud.y;
                
                //If not within the bounding box or obscured by an object, display the background directly.
                if (dstInCloud <= 0 || dstToObj <= dstToCloud)
                {
                    return half4(0, 0, 0, 1);
                }
                
                
                //Start Ray Marching
                //Set Sample Info
                SamplingInfo dsi;
                dsi.weatherTexTiling = _WeatherTexTiling;
                dsi.weatherTexOffset = _WeatherTexOffset;
                dsi.densityMultiplier = _DensityScale;
                dsi.cloudDensityAdjust = _CloudCover;
                dsi.windDirection = normalize(_WindDirecton);
                dsi.windSpeed = _WindSpeed;
                dsi.cloudHeightMinMax = _CloudHeightRange.xy;
                dsi.cloudOffsetLower = _CloudOffsetLower;
                dsi.cloudOffsetUpper = _CloudOffsetUpper;
                dsi.feather = _CloudFeather;
                dsi.sphereCenter = sphereCenter;
                dsi.earthRadius = earthRadius;
                
                
                
                //The position where it exits the cloud cover area (ending position).
                float endPos = dstToCloud + dstInCloud;
                float currentMarchLength = dstToCloud;
                //Current sample point
                float3 currentPos = cameraPos + currentMarchLength * viewDir;
                
                //total density
                float totalDensity = 0;
                
                
                //At first, step forward with a relatively large step size (twice the normal step length) for density sampling detection. 
                //When clouds are detected, step back to perform normal cloud sampling and lighting calculations. 
                // When a certain number of zero-density samples have been accumulated, switch back to larger steps to speed up the exit. 
                // Testing cloud density."
                float densityTest = 0;
                //Previous sample density
                float densityPrevious = 0;
                //the count of 0 density sample
                int densitySampleCount_zero = 0;
                
                
                //Begin stepping,end the stepping when exceeding the number of steps, being obstructed by an object, or exiting the cloud cover atmosphere.
                for (int marchNumber = 0; marchNumber < _ShapeMarchMax; marchNumber ++)
                {
                    //Initially take large steps forward. In baking mode, use SDF (Signed Distance Field) for rapid approximation.
                    if (densityTest == 0)
                    {
                        //Step forward a distance twice the length in the direction of observation.
                        currentMarchLength += _ShapeMarchLength * 2.0;
                        currentPos = cameraPos + currentMarchLength * viewDir;
                        
                        
                        //If the step reaches a point where it is obstructed by an object, or exits the cloud cover range, break out of the loop.
                        if (dstToObj <= currentMarchLength || endPos <= currentMarchLength)
                        {
                            break;
                        }
                        
                        //Conduct density sampling to test whether to continue taking large steps forward.
                        dsi.position = currentPos;
                        densityTest = SampleCloudDensity_No3DTex(dsi).density;
                        
                        //If clouds are detected, step back one step (as we might have missed the starting position).
                        if (densityTest > 0)
                        {
                            currentMarchLength -= _ShapeMarchLength;
                        }
                    }
                    else
                    {
                        //Sample the density of that area.
                        currentPos = cameraPos + currentMarchLength * viewDir;
                        dsi.position = currentPos;

                        CloudInfo ci = SampleCloudDensity_No3DTex(dsi);
                        
                            //If the current sampling density and the previous sampling density are both essentially zero, 
                            //then accumulate this information. When it reaches a specified value, switch to larger steps.
                            if (ci.density == 0 && densityPrevious == 0)
                            {
                                densitySampleCount_zero ++ ;
                                //Accumulate until a specified value is detected, then switch to large stepping.
                                if (densitySampleCount_zero >= 8)
                                {
                                    densityTest = 0;
                                    densitySampleCount_zero = 0;
                                    continue;
                                }
                            }
                        
                        float density = ci.density * _ShapeMarchLength;
                        
                        totalDensity += density;

                        currentMarchLength += _ShapeMarchLength;
                        // #endif
                        //If the step reaches a point where it is obstructed by an object, or exits the cloud cover range, exit the loop.
                        if (dstToObj <= currentMarchLength || endPos <= currentMarchLength)
                        {
                            break;
                        }
                        densityPrevious = ci.density;
                    }
                }
                // half4 cloudColor = totalDensity * _BaseColor;
                // half4 finalColor = cloudColor + backColor;
                return half4(totalDensity * _BaseColor.rgb,1);
                // return finalColor;
            }
            ENDHLSL
            
        }
        
        pass
        {
            //The first pass caclulate the cloud density
            //The second pass use Blend One SrcAlpha to blend the CameraColorTargetHandle to the sceen (mix previous screen color and cloud density result).
            Blend One SrcAlpha
            
            HLSLPROGRAM
            
            #pragma vertex vert_blend
            #pragma fragment frag_blend
            
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            struct appdata
            {
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };
            
            struct v2f
            {
                float4 vertex: SV_POSITION;
                float2 uv: TEXCOORD0;
            };
            
            v2f vert_blend(appdata v)
            {
                v2f o;
                
                VertexPositionInputs vertexPos = GetVertexPositionInputs(v.vertex.xyz);
                o.vertex = vertexPos.positionCS;
                o.uv = v.uv;
                return o;
            }
            
            half4 frag_blend(v2f i): SV_Target
            {
                return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * 0.3;
            }
            ENDHLSL
            
        }
    }
}
