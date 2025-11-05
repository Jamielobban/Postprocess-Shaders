Shader "Custom/CompressionBlocks"
{
    Properties
    {
        _BlockPx     ("Block Size (px)", Range(4,64)) = 8
        _Variation   ("Intra-Block Variation", Range(0,1)) = 0.2
        _BorderBoost ("Border Darken", Range(0,1)) = 0.25
        _ChromaShift ("Chroma Subsample Shift", Range(0,2)) = 0.5
        _Blend       ("Blend With Original", Range(0,1)) = 1
    }
    SubShader
    {
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "CompressionBlocksFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            float _BlockPx,_Variation,_BorderBoost,_ChromaShift,_Blend;

            float hash21(float2 p){
                p=frac(p*float2(123.34,345.45));
                p+=dot(p,p+34.345);
                return frac(p.x*p.y);
            }

            float4 Frag(Varyings i):SV_Target
            {
                float2 texSize=_BlitTexture_TexelSize.zw;
                float2 px      = 1.0/texSize;

                // block coords
                float2 blocks = texSize/_BlockPx;
                float2 id     = floor(i.texcoord*blocks);
                float2 uvBlock= (id + 0.5)/blocks; // block center sample (like heavy compression)

                // base sample (luma-ish)
                float3 base = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uvBlock).rgb;

                // chroma subsampling: shift R/B slightly inside each block
                float2 fracCell = frac(i.texcoord*blocks)-0.5;
                float2 shift = fracCell * (px*_ChromaShift*_BlockPx);
                float r = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uvBlock+shift).r;
                float b = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uvBlock-shift).b;
                float3 comp = float3(r, base.g, b);

                // intra-block variation (simulate quantization ringing)
                float rnd = (hash21(id+7.3)*2.0-1.0) * _Variation;
                comp += rnd * 0.02;

                // block border emphasis
                float2 f = abs(frac(i.texcoord*blocks)-0.5)*2.0; // 0 at center, 1 at edge
                float edge = smoothstep(0.8, 0.98, max(f.x,f.y)); // near border
                comp = lerp(comp, comp*(1.0-_BorderBoost), edge);

                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,i.texcoord).rgb;
                float3 outC = lerp(src, comp, _Blend);
                return float4(outC,1);
            }
            ENDHLSL
        }
    }
}
