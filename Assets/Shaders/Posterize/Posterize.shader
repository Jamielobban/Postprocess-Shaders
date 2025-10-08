Shader "Custom/BasePosterize"
{
    Properties
    {
        _Tint ("Tint Color", Color) = (1,1,1,1)
        _Bands ("Bands (>=2)", Range(2,32)) = 6
        [Toggle] _Perceptual ("Perceptual Quantize (approx sRGB)", Float) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalRenderPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullScreenPosterize"
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
            float  _Bands;
            float  _Perceptual;

            float3 PosterizeRGB(float3 rgb, float bands, bool perceptual)
            {
                // Clamp bands
                bands = max(bands, 2.0);

                // Optionally quantize in a perceptual space (approx sRGB)
                float3 c = saturate(rgb);
                if (perceptual)
                {
                    // Assume input is linear; go to perceptual, quantize, back to linear
                    float3 p = pow(c, 1.0 / 2.2);
                    p = floor(p * (bands - 1.0) + 0.5) / (bands - 1.0);
                    c = pow(p, 2.2);
                }
                else
                {
                    // Linear-space quantization
                    c = floor(c * (bands - 1.0) + 0.5) / (bands - 1.0);
                }
                return c;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.texcoord);

                float3 toon = PosterizeRGB(src.rgb, _Bands, (_Perceptual > 0.5));
                
                //toon = smoothstep(0.0, 1.0, toon);
                // Keep original alpha; apply your tint multiply
                return float4(toon, src.a) * _Tint;
            }
            ENDHLSL
        }
    }
}
