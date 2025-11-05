Shader "Custom/GlitchMeltWaveDepth"
{
    Properties
    {
        // Core melt
        [Toggle] _Vertical("Vertical Melt (on) / Horizontal (off)", Float) = 1
        _AmountPx   ("Displacement (px)", Range(0,64)) = 24
        _Tightness  ("Band Tightness", Range(0.1,4)) = 1.2

        // Wave / threshold sweep
        _WaveHz     ("Wave Speed (Hz)", Range(0,5)) = 0.35
        _WaveScale  ("Wave Scale", Range(0.1,10)) = 2.0
        _Threshold  ("Base Threshold", Range(0,1)) = 0.45
        _SweepAmp   ("Sweep Amplitude", Range(0,1)) = 0.35

        // Noise spice
        _NoiseAmp   ("Noise Amplitude", Range(0,1)) = 0.25
        _NoiseScale ("Noise Scale", Range(0.1,10)) = 3.0

        // Channel split (optional)
        _ChromaPx   ("Chromatic Split (px)", Range(0,4)) = 0.75

        // Depth fade / sky exclusion
        [Toggle] _UseDepthFade("Fade By Depth", Float) = 1
        _NearFade   ("Near Start", Float) = 20
        _FarFade    ("Far End",   Float) = 60

        _Blend      ("Blend With Original", Range(0,1)) = 1
        _Tint       ("Final Tint", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "GlitchMeltWaveDepthFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            
            TEXTURE2D_X_FLOAT(_CameraDepthTexture);  SAMPLER(sampler_CameraDepthTexture);

            float _Vertical, _AmountPx, _Tightness;
            float _WaveHz, _WaveScale, _Threshold, _SweepAmp;
            float _NoiseAmp, _NoiseScale, _ChromaPx;
            float _UseDepthFade, _NearFade, _FarFade;
            float _Blend; float4 _Tint;

            inline float Luma709(float3 c){ return dot(c, float3(0.2126,0.7152,0.0722)); }

            // Depth helpers
            float SampleLinearEyeDepth(float2 uv){
                float raw = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
                return LinearEyeDepth(raw, _ZBufferParams);
            }

            // Hash/noise
            float hash21(float2 p){
                p = frac(p * float2(123.34, 345.45));
                p += dot(p, p + 34.345);
                return frac(p.x * p.y);
            }
            float noise(float2 p){
                float2 i=floor(p), f=frac(p);
                float2 u=f*f*(3.0-2.0*f);
                float a=hash21(i+float2(0,0));
                float b=hash21(i+float2(1,0));
                float c=hash21(i+float2(0,1));
                float d=hash21(i+float2(1,1));
                return lerp(lerp(a,b,u.x), lerp(c,d,u.x), u.y);
            }

            float4 Frag(Varyings i) : SV_Target
            {
                float2 texel = _BlitTexture_TexelSize.xy;
                float2 texSize = _BlitTexture_TexelSize.zw;
                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord).rgb;

                // Depth fade: skip sky/far plane
                float fade = 1.0;
                if (_UseDepthFade > 0.5){
                    float d = SampleLinearEyeDepth(i.texcoord);
                    fade = saturate(1.0 - smoothstep(_NearFade, _FarFade, d));
                    if (fade <= 0.001) return float4(src,1) * _Tint;
                }

                // Luminance as driver
                float lum = Luma709(src);

                // Moving threshold sweep (sine over time)
                float t = _Time.y * (6.2831853 * _WaveHz);
                // coordinate along bands: x for vertical melt, y for horizontal
                float lane = (_Vertical > 0.5) ? i.texcoord.x : i.texcoord.y;

                float wave = 0.5 + 0.5 * sin(lane * _WaveScale * 6.2831853 + t);
                float thr  = saturate(_Threshold + (wave - 0.5) * 2.0 * _SweepAmp);

                // Add procedural noise to break uniformity
                float2 ncoord = i.texcoord * _NoiseScale + float2(t*0.12, -t*0.07);
                float n = (noise(ncoord) - 0.5) * 2.0 * _NoiseAmp;
                thr = saturate(thr + n);

                // Band mask: areas above threshold will "melt"
                // Tightness controls the transition hardness
                float band = smoothstep(thr - (0.25/_Tightness), thr + (0.25/_Tightness), lum);

                // Displacement amount in UVs (pixels -> UV)
                float2 disp = 0;
                float amtUV = (_AmountPx / ((_Vertical > 0.5) ? texSize.y : texSize.x)); // convert px to UV on displacement axis

                // Shape the displacement with band strength (cubic for heavier centers)
                float shaped = band * band * (3.0 - 2.0 * band);

                if (_Vertical > 0.5){
                    // vertical melt => displace along +Y
                    disp.y = shaped * amtUV;
                } else {
                    // horizontal melt => displace along +X
                    disp.x = shaped * amtUV;
                }

                // Optional chromatic split for extra VHS-y tear
                float2 cab = (_Vertical > 0.5) ? float2(0, _ChromaPx/texSize.y) : float2(_ChromaPx/texSize.x, 0);

                float r = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord + disp + cab).r;
                float g = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord + disp         ).g;
                float b = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord + disp - cab).b;
                float3 melted = float3(r,g,b);

                float3 outC = lerp(src, melted, _Blend * fade);
                return float4(outC, 1) * _Tint;
            }
            ENDHLSL
        }
    }
}
