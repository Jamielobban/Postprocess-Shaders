Shader "Custom/BitCrush"
{
    Properties
    {
        _BitsR ("Bits R", Range(1,8)) = 4
        _BitsG ("Bits G", Range(1,8)) = 4
        _BitsB ("Bits B", Range(1,8)) = 4
        [Toggle] _Dither("Ordered Dither", Float) = 1
        _DitherStrength("Dither Strength", Range(0,1)) = 0.25
        _Blend ("Blend With Original", Range(0,1)) = 1
    }
    SubShader
    {
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "BitCrushFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            
            float _BitsR,_BitsG,_BitsB,_Dither,_DitherStrength,_Blend;

            float bayer4x4(uint2 p){
                const float M[16]={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5};
                uint idx=((p.y&3)<<2)|(p.x&3);
                return (M[idx]+0.5)/16.0;
            }

            float crush(float v, float bits, float jitter)
            {
                float steps = pow(2.0, bits);
                v = saturate(v + jitter/steps);
                return floor(v*steps)/(steps-1.0);
            }

            float4 Frag(Varyings i):SV_Target
            {
                float3 src=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,i.texcoord).rgb;

                float j=0;
                if(_Dither>0.5){
                    uint2 px = uint2(i.texcoord * _BlitTexture_TexelSize.zw);
                    j = (bayer4x4(px)-0.5)*2.0*_DitherStrength; // -s..+s
                }

                float3 c;
                c.r = crush(src.r,_BitsR,j);
                c.g = crush(src.g,_BitsG,j*0.9);
                c.b = crush(src.b,_BitsB,j*0.8);

                return float4(lerp(src,c,_Blend),1);
            }
            ENDHLSL
        }
    }
}
