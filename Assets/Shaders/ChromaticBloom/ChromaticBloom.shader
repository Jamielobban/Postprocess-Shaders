Shader "Custom/ChromaticBloom"
{
    Properties
    {
        _Threshold   ("Bloom Threshold", Range(0,5)) = 1.0
        _Intensity   ("Bloom Intensity", Range(0,3)) = 1.2
        _RadiusPx    ("Blur Radius (px)", Range(1,12)) = 6
        _Spectral    ("Spectral Shift (px)", Range(0,3)) = 1.0
        [Toggle] _Additive ("Additive Blend (else screen-like)", Float) = 1

        [Toggle] _UseDepthFade("Fade By Depth", Float) = 1
        _NearFade   ("Near Start", Float) = 20
        _FarFade    ("Far End",   Float) = 60
        _Tint       ("Final Tint", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "ChromaticBloomFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

            float _Threshold,_Intensity,_RadiusPx,_Spectral,_Additive;
            float _UseDepthFade,_NearFade,_FarFade; float4 _Tint;

            inline float Luma709(float3 c){ return dot(c,float3(0.2126,0.7152,0.0722)); }
            float SampleLinearEyeDepth(float2 uv)
            {
                float raw=SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv).r;
                return LinearEyeDepth(raw,_ZBufferParams);
            }

            float3 BlurSpectral(float2 uv, float2 texel)
            {
                // 9-tap roughly Gaussian, with per-channel radial shift
                float rpx=max(1.0,_RadiusPx);
                float2 stepUV = texel*rpx/3.0;

                float w[5]={0.227027f,0.1945946f,0.1216216f,0.054054f,0.016216f};
                float3 acc=0; float wsum=0;

                // center (no shift)
                float3 c0=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv).rgb;
                acc+=c0*w[0]; wsum+=w[0];

                [unroll] for(int k=1;k<5;k++)
                {
                    float2 o=stepUV*k;

                    // small chromatic divergence
                    float2 offR = o + _Spectral*texel*k;
                    float2 offB = o - _Spectral*texel*k;

                    float3 cP = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv+o).rgb;
                    float3 cM = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv-o).rgb;

                    // apply per-channel shifts
                    float3 rp = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv+offR).rgb;
                    float3 bm = SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv-offB).rgb;

                    float3 plus  = float3(rp.r, cP.g, cP.b);
                    float3 minus = float3(cM.r, cM.g, bm.b);

                    acc += (plus + minus)*w[k];
                    wsum+= 2*w[k];
                }
                return acc/max(wsum,1e-4);
            }

            float4 Frag(Varyings i):SV_Target
            {
                float3 src=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,i.texcoord).rgb;

                // depth fade to ignore sky/far
                float fade=1.0;
                if(_UseDepthFade>0.5)
                {
                    float d=SampleLinearEyeDepth(i.texcoord);
                    fade=saturate(1.0 - smoothstep(_NearFade,_FarFade,d));
                    if(fade<=0.001) return float4(src,1)*_Tint;
                }

                // bright-pass
                float3 pre=src;
                float lum=Luma709(pre);
                float3 thr=max(pre - _Threshold, 0);
                thr*=thr; // soft knee

                // blur the bright areas
                float2 texel=_BlitTexture_TexelSize.xy;
                // multiply source by bright mask before blurring (cheaper bright-pass)
                // sample from a virtual “bright” image using masking around taps
                // (approx by multiplying the blurred result)
                float3 blurred=BlurSpectral(i.texcoord,texel) * saturate(Luma709(BlurSpectral(i.texcoord,texel))>0?1:1);

                // final bloom color derives from bright-pass multiplied pre-blur
                float3 bloom=BlurSpectral(i.texcoord,texel) * _Intensity;

                // composite
                float3 outC;
                if(_Additive>0.5) outC=src + bloom*fade;
                else              outC=1-(1-src)*(1-saturate(bloom*fade)); // screen-like

                return float4(outC,1)*_Tint;
            }
            ENDHLSL
        }
    }
}
