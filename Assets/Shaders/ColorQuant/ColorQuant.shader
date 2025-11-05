Shader "Custom/ColorQuantization"
{
    Properties{
        _Levels("Color Levels", Range(2,32)) = 6
        _Blend("Blend With Original", Range(0,1)) = 1
    }
    SubShader{
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass{
            Name "ColorQuantizationFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Levels,_Blend;

            float4 Frag(Varyings i):SV_Target{
                float3 c = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,i.texcoord).rgb;
                float lv=max(2.0,_Levels);
                // convert to YUV-like for perceptual spacing
                float3 yuv = float3(dot(c,float3(0.299,0.587,0.114)),
                                    dot(c,float3(-0.14713,-0.28886,0.436)),
                                    dot(c,float3(0.615,-0.51499,-0.10001)));
                yuv=floor(yuv*lv)/lv;
                // back to RGB
                float3 q = float3(yuv.x + 1.13983*yuv.z,
                                  yuv.x - 0.39465*yuv.y - 0.58060*yuv.z,
                                  yuv.x + 2.03211*yuv.y);
                c = lerp(c,saturate(q),_Blend);
                return float4(c,1);
            }
            ENDHLSL
        }
    }
}
