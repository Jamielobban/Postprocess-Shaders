Shader "Custom/FullscreenDitherURP_Mono_Readable"
{
    Properties
    {
        _Tint ("Tint Color", Color) = (1,1,1,1)
        _DitherStrength ("Dither Strength (0-1)", Range(0,1)) = 1
        _DitherScale ("Pattern Pixel Size (1..8)", Range(1,8)) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullScreenDitherMono"
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _Tint;
            float  _DitherStrength;   // 0..1 (0 = original, 1 = pure B/W dither)
            float  _DitherScale;      // how many screen pixels share one Bayer cell

            // 4x4 Bayer thresholds as integers 0..15 (classic pattern)
            static const float BAYER4[16] = {
                 0,  8,  2, 10,
                12,  4, 14,  6,
                 3, 11,  1,  9,
                15,  7, 13,  5
            };


            // Convert RGB to perceptual luma (monochrome)
            float Luma(float3 rgb) { return dot(rgb, float3(0.299, 0.587, 0.114)); }

            // Readable Bayer threshold lookup in [0,1)
            float Bayer4x4Threshold_Readable(int2 pixelXY, float ditherScale)
            {
                // 1) Optionally coarsen screen pixels so each threshold covers a block
                float s = max(1.0, ditherScale);
                int2 cellCoord = int2(floor(pixelXY / s)); // discrete “pattern cell” coords

                // 2) Wrap into 4x4 tile using % (modulo)
                int x = cellCoord.x % 4; if (x < 0) x += 4; // safe mod for completeness
                int y = cellCoord.y % 4; if (y < 0) y += 4;

                // 3) Flatten (x,y) -> 0..15
                int idx = y * 4 + x;

                // 4) Map 0..15 to [0,1). +0.5 centers each bin
                return (BAYER4[idx] + 0.5) / 16.0;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                // Source color (post tonemap if you place the pass AfterRenderingPostProcessing)
                float2 uv  = input.texcoord;
                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv) * _Tint;

                // Turn UV (0..1) into integer pixel coords (0..width-1 / 0..height-1)
                int2 pixelXY = int2(floor(uv * _ScreenParams.xy));

                // Per-pixel threshold from the 4x4 Bayer tile
                float t = Bayer4x4Threshold_Readable(pixelXY, _DitherScale);

                // Monochrome decision via luma; step(t,g) returns 0 or 1
                float g  = Luma(src.rgb);
                float on = step(t, g);

                // Use the same value for R,G,B -> (0,0,0) or (1,1,1)
                float3 dithered = float3(on, on, on);

                // Blend between original and hard dither
                float3 outRGB = lerp(src.rgb, dithered, _DitherStrength);

                return float4(outRGB, src.a);
            }
            ENDHLSL
        }
    }
}
