Shader "Custom/PaletteLuminanceTex"
{
    Properties{
        _PaletteTex("Palette (horizontal strip)", 2D) = "white" {}
        _Steps("Colors (<= palette width)", Range(2,64)) = 4
        _Blend("Blend With Original", Range(0,1)) = 1

        // Luminance shaping
        _BlackPoint("Black Point", Range(0,1)) = 0.0
        _WhitePoint("White Point", Range(0,1)) = 1.0
        _Gamma("Perceptual Gamma", Range(0.1,3)) = 1.0
        [Toggle] _AutoExposure("Auto-Expose (use mip avg)", Float) = 1

        // Dithering
        [Toggle] _Dither("Ordered Dither", Float) = 1
        _DitherStrength("Dither Strength", Range(0,1)) = 0.35
    }
    SubShader{
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass{
            Name "PaletteLuminanceTexFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_PaletteTex);     SAMPLER(sampler_PaletteTex);
            float4 _PaletteTex_TexelSize; // x=1/w, y=1/h, z=w, w=h

            float _Steps, _Blend;
            float _BlackPoint, _WhitePoint, _Gamma, _AutoExposure;
            float _Dither, _DitherStrength;

            // Rec.709 luma (linear)
            inline float Luma709(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

            // 4x4 Bayer matrix
            float bayer4x4(uint2 p)
            {
                const float M[16] = {
                    0,  8,  2, 10,
                    12, 4, 14, 6,
                    3, 11, 1,  9,
                    15, 7, 13, 5
                };
                uint idx = ((p.y & 3) << 2) | (p.x & 3);
                return (M[idx] + 0.5) / 16.0; // 0..1
            }

            // Rough average luminance via high mip of _BlitTexture
            float AvgLuma()
            {
                // choose a small mip ~16x16
                float w = max(1.0, _BlitTexture_TexelSize.z);
                float h = max(1.0, _BlitTexture_TexelSize.w);
                float maxDim = max(w, h);
                float lod = max(0.0, log2(maxDim) - 4.0); // target ≈16px
                float3 c = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, float2(0.5,0.5), lod).rgb;
                return Luma709(c);
            }

            float4 Frag(Varyings i) : SV_Target
            {
                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord).rgb;

                // 1) Luminance (linear)
                float lum = Luma709(src);

                // 2) Optional auto exposure: normalize around scene average
                if (_AutoExposure > 0.5)
                {
                    float avg = AvgLuma();
                    // Simple gain to push average toward mid-gray (0.5)
                    float gain = (avg > 1e-4) ? (0.5 / avg) : 1.0;
                    lum = saturate(lum * gain);
                }

                // 3) Black/White point remap then gamma
                float range = max(1e-5, _WhitePoint - _BlackPoint);
                lum = saturate((lum - _BlackPoint) / range);
                lum = pow(lum, max(0.1, _Gamma)); // perceptual shaping

                // 4) Dithered quantization to N steps
                float paletteWidth = max(2.0, _PaletteTex_TexelSize.z);
                float steps = clamp(_Steps, 2.0, paletteWidth);

                if (_Dither > 0.5)
                {
                    uint2 px = uint2(i.texcoord * _BlitTexture_TexelSize.zw); // integer pixel
                    float d = (bayer4x4(px) - 0.5) * _DitherStrength; // -s..+s
                    lum = saturate(lum + d / steps); // small pre-quant jitter
                }

                float idx = floor(lum * (steps - 1.0)) / (steps - 1.0);

                // 5) Sample palette texel center at chosen index (row center = 0.5)
                float2 uvPal = float2(idx, 0.5);
                float3 pal   = SAMPLE_TEXTURE2D(_PaletteTex, sampler_PaletteTex, uvPal).rgb;

                float3 outc = lerp(src, pal, _Blend);
                return float4(outc, 1);
            }
            ENDHLSL
        }
    }
}
