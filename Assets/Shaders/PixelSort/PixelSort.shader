Shader "Custom/PixelSort"
{
    Properties{
        _Strength("Stretch Strength", Range(0,1)) = 0.6
        _Threshold("Brightness Cut", Range(0,1)) = 0.4
        _Direction("Direction (1=Right, -1=Left)", Float) = 1
    }
    SubShader{
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass{
            Name "PixelSortFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Strength,_Threshold,_Direction;

            float4 Frag(Varyings i):SV_Target{
                float2 texel=_BlitTexture_TexelSize.xy;
                float3 c=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,i.texcoord).rgb;
                float lum=dot(c,float3(0.299,0.587,0.114));
                if(lum>_Threshold){
                    float shift = (lum-_Threshold)*_Strength*0.5*_Direction;
                    i.texcoord.x = saturate(i.texcoord.x+shift);
                }
                float3 outC=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,i.texcoord).rgb;
                return float4(outC,1);
            }
            ENDHLSL
        }
    }
}
