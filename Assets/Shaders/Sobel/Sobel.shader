Shader "Custom/SobelOutline_ColorDepthNormal_URP"
{
    Properties
    {
        _EdgeColor     ("Edge Color", Color) = (0,0,0,1)
        _Blend         ("Blend With Source (0=edges only,1=overlay)", Range(0,1)) = 1

        // Response shaping
        _Threshold     ("Global Threshold", Range(0,1)) = 0.2
        _Strength      ("Global Strength", Range(0,10)) = 3

        // Channel weights (set to 0 to disable a channel)
        _ColorWeight   ("Color Edge Weight",   Range(0,2)) = 1
        _DepthWeight   ("Depth Edge Weight",   Range(0,2)) = 1
        _NormalWeight  ("Normal Edge Weight",  Range(0,2)) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalRenderPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "Sobel_ColorDepthNormal"
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // _ZBufferParams, GetScaledScreenParams()
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

            // Declares _CameraDepthTexture + SampleSceneDepth()
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // Declares _CameraNormalsTexture + SampleSceneNormals()
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            float4 _EdgeColor;
            float  _Blend;
            float  _Threshold, _Strength;
            float  _ColorWeight, _DepthWeight, _NormalWeight;

            inline float Luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

            // --- Sobel on color (sampled at blit RT resolution) ---
            float SobelColorMag(float2 uv)
            {
                float2 t = _BlitTexture_TexelSize.xy;

                float3 c00 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-t.x, -t.y)).rgb;
                float3 c10 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( 0.0 , -t.y)).rgb;
                float3 c20 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( t.x,  -t.y)).rgb;

                float3 c01 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-t.x,  0.0 )).rgb;
                float3 c11 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( 0.0 ,  0.0 )).rgb;
                float3 c21 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( t.x,   0.0 )).rgb;

                float3 c02 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-t.x,  t.y)).rgb;
                float3 c12 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( 0.0 ,  t.y)).rgb;
                float3 c22 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( t.x,   t.y)).rgb;

                float l00=Luma(c00), l10=Luma(c10), l20=Luma(c20);
                float l01=Luma(c01), l11=Luma(c11), l21=Luma(c21);
                float l02=Luma(c02), l12=Luma(c12), l22=Luma(c22);

                float gx = (-1*l00) + ( 0*l10) + ( 1*l20)
                         + (-2*l01) + ( 0*l11) + ( 2*l21)
                         + (-1*l02) + ( 0*l12) + ( 1*l22);

                float gy = (-1*l00) + (-2*l10) + (-1*l20)
                         + ( 0*l01) + ( 0*l11) + ( 0*l21)
                         + ( 1*l02) + ( 2*l12) + ( 1*l22);

                return sqrt(gx*gx + gy*gy);
            }

            // --- Sobel on linear01 depth (neighbor step = scaled backbuffer pixel) ---
            float SobelDepthMag(float2 uv)
            {
                float2 px = 1.0 / GetScaledScreenParams().xy;

                float d00 = Linear01Depth(SampleSceneDepth(uv + float2(-px.x, -px.y)), _ZBufferParams);
                float d10 = Linear01Depth(SampleSceneDepth(uv + float2( 0.0 , -px.y)), _ZBufferParams);
                float d20 = Linear01Depth(SampleSceneDepth(uv + float2( px.x, -px.y)), _ZBufferParams);
                float d01 = Linear01Depth(SampleSceneDepth(uv + float2(-px.x,  0.0 )), _ZBufferParams);
                float d11 = Linear01Depth(SampleSceneDepth(uv + float2( 0.0 ,  0.0 )), _ZBufferParams);
                float d21 = Linear01Depth(SampleSceneDepth(uv + float2( px.x,  0.0 )), _ZBufferParams);
                float d02 = Linear01Depth(SampleSceneDepth(uv + float2(-px.x,  px.y)), _ZBufferParams);
                float d12 = Linear01Depth(SampleSceneDepth(uv + float2( 0.0 ,  px.y)), _ZBufferParams);
                float d22 = Linear01Depth(SampleSceneDepth(uv + float2( px.x,  px.y)), _ZBufferParams);

                float gx = (-1*d00) + ( 0*d10) + ( 1*d20)
                         + (-2*d01) + ( 0*d11) + ( 2*d21)
                         + (-1*d02) + ( 0*d12) + ( 1*d22);

                float gy = (-1*d00) + (-2*d10) + (-1*d20)
                         + ( 0*d01) + ( 0*d11) + ( 0*d21)
                         + ( 1*d02) + ( 2*d12) + ( 1*d22);

                return sqrt(gx*gx + gy*gy);
            }

            // --- Sobel on view-space normals (neighbor step = scaled backbuffer pixel) ---
            float SobelNormalMag(float2 uv)
            {
                float2 px = 1.0 / GetScaledScreenParams().xy;

                float3 n00 = SampleSceneNormals(uv + float2(-px.x, -px.y));
                float3 n10 = SampleSceneNormals(uv + float2( 0.0 , -px.y));
                float3 n20 = SampleSceneNormals(uv + float2( px.x, -px.y));
                float3 n01 = SampleSceneNormals(uv + float2(-px.x,  0.0 ));
                float3 n11 = SampleSceneNormals(uv + float2( 0.0 ,  0.0 ));
                float3 n21 = SampleSceneNormals(uv + float2( px.x,  0.0 ));
                float3 n02 = SampleSceneNormals(uv + float2(-px.x,  px.y));
                float3 n12 = SampleSceneNormals(uv + float2( 0.0 ,  px.y));
                float3 n22 = SampleSceneNormals(uv + float2( px.x,  px.y));

                // Normalize for stability (texture usually packed as -1..1 already)
                n00 = normalize(n00); n10 = normalize(n10); n20 = normalize(n20);
                n01 = normalize(n01); n11 = normalize(n11); n21 = normalize(n21);
                n02 = normalize(n02); n12 = normalize(n12); n22 = normalize(n22);

                float3 gxv = (-1*n00) + ( 0*n10) + ( 1*n20)
                           + (-2*n01) + ( 0*n11) + ( 2*n21)
                           + (-1*n02) + ( 0*n12) + ( 1*n22);

                float3 gyv = (-1*n00) + (-2*n10) + (-1*n20)
                           + ( 0*n01) + ( 0*n11) + ( 0*n21)
                           + ( 1*n02) + ( 2*n12) + ( 1*n22);

                return sqrt(dot(gxv,gxv) + dot(gyv,gyv));
            }

            float4 Frag(Varyings i) : SV_Target
            {
                float2 uv = i.texcoord;

                // Per-channel edge magnitudes
                float eColor  = SobelColorMag(uv)  * _ColorWeight;
                float eDepth  = SobelDepthMag(uv)  * _DepthWeight;
                float eNormal = SobelNormalMag(uv) * _NormalWeight;

                // Combine: max gives crisp lines; change to sum for heavier silhouettes
                float edge = max(eColor, max(eDepth, eNormal));

                // Shape and blend
                float mask = saturate((edge - _Threshold) * _Strength);

                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
                float4 edgesCol = float4(_EdgeColor.rgb, 1) * mask;

                // 0 = edges only, 1 = overlay on source
                return lerp(edgesCol, lerp(src, float4(_EdgeColor.rgb, 1), mask), _Blend);
            }
            ENDHLSL
        }
    }
}
