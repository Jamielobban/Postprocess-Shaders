Shader "Custom/BaseColorDither"
{
    Properties
    {
        _Tint        ("Tint Color", Color) = (1,1,1,1)
        _BandsRGB    ("Bands R,G,B (>=2)", Vector) = (6,6,6,0)
        _DitherScale ("Dither Cell Size", Range(1,8)) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalRenderPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullScreenColorDither"
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
            float4 _BandsRGB;     // xyz = bands per channel (>=2)
            float  _DitherScale;  // 1 = native pixel, 2+ = coarser pattern

            // Bayer 4x4 threshold in [0,1)
            float Bayer4x4(int2 p)
            {
                // 4x4 Bayer matrix values [0..15]
                //  0  8  2 10
                // 12  4 14  6
                //  3 11  1  9
                // 15  7 13  5
                static const int4 row0 = int4( 0,  8,  2, 10);
                static const int4 row1 = int4(12,  4, 14,  6);
                static const int4 row2 = int4( 3, 11,  1,  9);
                static const int4 row3 = int4(15,  7, 13,  5);

                int x = p.x & 3; // %4
                int y = p.y & 3;

                int v = (y == 0) ? row0[x]
                      : (y == 1) ? row1[x]
                      : (y == 2) ? row2[x]
                                 : row3[x];

                return (v + 0.5) / 16.0; // map 0..15 -> [0,1)
            }

            // Quantize one channel with ordered thresholding
            float QuantizeOrdered(float c, float bands, float t)
            {
                bands = max(bands, 2.0);
                float q = floor(saturate(c) * (bands - 1.0) + t);
                return q / (bands - 1.0);
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.texcoord);

                // Pixel coords (optionally coarsened by _DitherScale)
                float2 uv  = GetNormalizedScreenSpaceUV(input.positionCS);
                float2 res = _ScreenParams.xy;
                float  s   = max(1.0, _DitherScale);
                int2   pix = int2(floor(uv * (res / s)));

                float t = Bayer4x4(pix); // [0,1)

                float3 bands = max(_BandsRGB.xyz, float3(2.0, 2.0, 2.0));

                float3 dithered;
                dithered.r = QuantizeOrdered(src.r, bands.r, t);
                dithered.g = QuantizeOrdered(src.g, bands.g, t);
                dithered.b = QuantizeOrdered(src.b, bands.b, t);

                return float4(dithered, src.a) * _Tint;
            }
            ENDHLSL
        }
    }
}
