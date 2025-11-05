Shader "Custom/DMG_4Color"
{
    Properties
    {
        // 4-color palette from darkest -> lightest (DMG-ish defaults)
        _Color0 ("Color 0 (Darkest)", Color) = (0.106, 0.149, 0.047, 1)
        _Color1 ("Color 1",            Color) = (0.275, 0.361, 0.122, 1)
        _Color2 ("Color 2",            Color) = (0.553, 0.667, 0.271, 1)
        _Color3 ("Color 3 (Lightest)", Color) = (0.871, 0.929, 0.549, 1)

        // Thresholds split grayscale into 4 bins
        _T1 ("Threshold 1", Range(0,1)) = 0.25
        _T2 ("Threshold 2", Range(0,1)) = 0.50
        _T3 ("Threshold 3", Range(0,1)) = 0.75

        // Dithering
        [Toggle] _UseDither ("Use 4x4 Ordered Dither", Float) = 1
        _DitherStrength ("Dither Strength", Range(0,0.5)) = 0.15

        // Mix with original (0 = original, 1 = full 4-color)
        _Contribution ("Contribution", Range(0,1)) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullScreen4Color"
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _Color0, _Color1, _Color2, _Color3;
            float _T1, _T2, _T3;
            float _UseDither, _DitherStrength;
            float _Contribution;

            // 4x4 Bayer matrix as a function (integer math, stable pattern)
            float bayer4(int2 p)
            {
                int x = p.x & 3;
                int y = p.y & 3;

                // Values 0..15 laid out explicitly
                if (y == 0) { if (x == 0) return 0.0/16.0; if (x == 1) return 8.0/16.0; if (x == 2) return 2.0/16.0; return 10.0/16.0; }
                if (y == 1) { if (x == 0) return 12.0/16.0; if (x == 1) return 4.0/16.0; if (x == 2) return 14.0/16.0; return 6.0/16.0; }
                if (y == 2) { if (x == 0) return 3.0/16.0; if (x == 1) return 11.0/16.0; if (x == 2) return 1.0/16.0; return 9.0/16.0; }
                /* y == 3 */ if (x == 0) return 15.0/16.0; if (x == 1) return 7.0/16.0;  if (x == 2) return 13.0/16.0; return 5.0/16.0;
            }

            float3 toGrayRGB(float3 c)
            {
                // Luminance in linear space (URP camera buffer is linear)
                float l = dot(c, float3(0.2126, 0.7152, 0.0722));
                return float3(l, l, l);
            }

            float4 Frag(Varyings i) : SV_Target
            {
                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord);

                // Grayscale value (0..1)
                float l = dot(src.rgb, float3(0.2126, 0.7152, 0.0722));

                // Optional ordered dithering: push luminance up/down by a tiny offset
                if (_UseDither > 0.5)
                {
                    // Convert UV to pixel coords (stable across resolutions)
                    int2 p = int2(i.texcoord * _ScreenParams.xy);
                    float d = bayer4(p) - 0.5;                  // [-0.5, 0.5]
                    l = saturate(l + d * _DitherStrength);       // small bias for thresholding
                }

                // 4-band quantization based on thresholds
                float3 q;
                if (l < _T1)       q = _Color0.rgb;
                else if (l < _T2)  q = _Color1.rgb;
                else if (l < _T3)  q = _Color2.rgb;
                else               q = _Color3.rgb;

                // Mix with original
                float3 outRGB = lerp(src.rgb, q, _Contribution);
                return float4(outRGB, 1);
            }
            ENDHLSL
        }
    }
}
