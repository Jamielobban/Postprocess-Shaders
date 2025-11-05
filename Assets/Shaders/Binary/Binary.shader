Shader "Custom/BinaryThreshold"
{
    Properties{
        _Threshold("Luminance Threshold", Range(0,1)) = 0.5
        _DarkColor("Dark Color", Color) = (0,0,0,1)
        _LightColor("Light Color", Color) = (1,1,1,1)
    }
    SubShader{
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass{
            Name "BinaryThresholdFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            float _Threshold; float4 _DarkColor,_LightColor;
            float4 Frag(Varyings i):SV_Target{
                float3 c=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,i.texcoord).rgb;
                float lum=dot(c,float3(0.299,0.587,0.114));
                return (lum>_Threshold)?_LightColor:_DarkColor;
            }
            ENDHLSL
        }
    }
}
