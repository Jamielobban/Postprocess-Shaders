Shader "Custom/Base"
{
    Properties
    {
        _Tint ("Tint Color", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalRenderPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullScreenTint"
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

            float4 Frag(Varyings input) : SV_Target
            {
                // Tint over the opaque source
                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.texcoord);
                return src * _Tint;
            }
            ENDHLSL
        }
    }
}
