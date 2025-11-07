Shader "Custom/FullscreenDitherURP_BayerPro"
{
    Properties
    {
        _Tint ("Tint Color", Color) = (1,1,1,1)
        _DitherStrength ("Dither Strength (0-1)", Range(0,1)) = 1
        _DitherScale ("Base Pattern Pixel Size (1..8)", Range(1,8)) = 1

        // Pattern selector (local keywords only)
        [KeywordEnum(Bayer2x2,Bayer4x4,Bayer8x8)]
        _Pattern ("Pattern", Float) = 1

        // --- Tone shaping ---
        _Gamma ("Luma Gamma", Range(0.2,2.5)) = 1.0
        _Lift  ("Lift", Range(-0.2,0.2)) = 0.00
        _Gain  ("Gain", Range(0.5,1.5)) = 1.00

        // --- Quantization ---
        [Toggle] _UseQuantize ("Use N-Level Quantization", Float) = 1
        _Levels ("Levels (>=2)", Range(2,16)) = 6

        // Per-channel RGB quantization (stylized)
        [Toggle] _UseRGBChannels ("Per-Channel RGB Quantize", Float) = 0

        // --- Depth masking (requires depth texture in URP pipeline) ---
        [Toggle] _UseDepthMask ("Use Depth Mask", Float) = 1
        _NearOn ("Depth Near On (m)", Range(0.0,10.0)) = 0.5
        _FarOff ("Depth Far Off (m)", Range(1.0,200.0)) = 40.0

        // Pattern scale by depth (smaller cells far away)
        [Toggle] _UseDepthScale ("Scale Pattern By Depth", Float) = 1
        _ScaleNear ("Scale Near (x)", Range(0.5,4.0)) = 1.0
        _ScaleFar  ("Scale Far (x)",  Range(0.5,8.0)) = 4.0

        // --- Edge-aware mixing ---
        [Toggle] _UseEdgeMask ("Use Edge-Aware Mix", Float) = 1
        _EdgeAmount ("Edge Reduction Amount", Range(0.0,2.0)) = 1.0

        // --- Temporal interleave (tiny jitter) ---
        [Toggle] _UseTemporal ("Use Temporal Jitter", Float) = 1
        _TemporalAmount ("Temporal Amount", Range(0.0,1.0)) = 0.25
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullscreenDither_BayerPro"
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag

            // Local variants so they don't pollute global keywords
            #pragma shader_feature_local _PATTERN_BAYER2X2 _PATTERN_BAYER4X4 _PATTERN_BAYER8X8

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _Tint;
                float  _DitherStrength;
                float  _DitherScale;

                float  _Gamma;
                float  _Lift;
                float  _Gain;

                float  _UseQuantize;
                float  _Levels;
                float  _UseRGBChannels;

                float  _UseDepthMask;
                float  _NearOn;
                float  _FarOff;

                float  _UseDepthScale;
                float  _ScaleNear;
                float  _ScaleFar;

                float  _UseEdgeMask;
                float  _EdgeAmount;

                float  _UseTemporal;
                float  _TemporalAmount;
            CBUFFER_END

            // --- Utilities ---
            float Luma(float3 rgb) { return dot(rgb, float3(0.299, 0.587, 0.114)); }

            // Tiny hash, used for per-channel offsets
            float Hash21(uint2 p)
            {
                uint n = p.x * 0x27d4eb2d + p.y * 0x165667b1;
                n = (n ^ (n >> 15)) * 0x85ebca6b ^ 0xc2b2ae35;
                n ^= (n >> 13);
                return (n & 0x00FFFFFF) / 16777216.0;
            }

            // Sample linear eye depth (meters). Needs depth texture enabled in URP.
            float SampleEyeDepth(float2 uv)
            {
                #if defined(UNITY_REVERSED_Z)
                    float raw = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_LinearClamp, uv).r;
                #else
                    float raw = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_LinearClamp, uv).r;
                #endif
                return LinearEyeDepth(raw, _ZBufferParams);
            }

            // Pattern cell helper
            int2 PatternCell(int2 pix, float scale)
            {
                int s = (int)max(1.0, floor(scale + 0.5));
                return pix / max(1, s);
            }

            // --- Bayer matrices ---
            static const float BAYER2[4] = { 0, 2, 3, 1 };
            static const float BAYER4[16] = {
                 0,  8,  2, 10,
                12,  4, 14,  6,
                 3, 11,  1,  9,
                15,  7, 13,  5
            };
            static const float BAYER8[64] = {
                 0,48,12,60, 3,51,15,63,
                32,16,44,28,35,19,47,31,
                 8,56, 4,52,11,59, 7,55,
                40,24,36,20,43,27,39,23,
                 2,50,14,62, 1,49,13,61,
                34,18,46,30,33,17,45,29,
                10,58, 6,54, 9,57, 5,53,
                42,26,38,22,41,25,37,21
            };

            // Normalized threshold helpers (0..1)
            float T_Bayer2(int2 c){ int x=(c.x%2+2)%2; int y=(c.y%2+2)%2; return (BAYER2[y*2+x]+0.5)/4.0; }
            float T_Bayer4(int2 c){ int x=(c.x%4+4)%4; int y=(c.y%4+4)%4; return (BAYER4[y*4+x]+0.5)/16.0; }
            float T_Bayer8(int2 c){ int x=(c.x%8+8)%8; int y=(c.y%8+8)%8; return (BAYER8[y*8+x]+0.5)/64.0; }

            // Unified threshold
            float DitherThreshold(int2 pixelXY, float scaledPattern)
            {
                int2 cell = PatternCell(pixelXY, scaledPattern);
                #if defined(_PATTERN_BAYER2X2)
                    return T_Bayer2(cell);
                #elif defined(_PATTERN_BAYER4X4)
                    return T_Bayer4(cell);
                #elif defined(_PATTERN_BAYER8X8)
                    return T_Bayer8(cell);
                #else
                    return T_Bayer4(cell);
                #endif
            }

            // Edge mask from tiny cross sample (0 = edge, 1 = flat)
            float EdgeMask(float2 uv)
            {
                float2 px = 1.0 / _ScreenParams.xy;
                float3 c0 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-px.x, 0)).rgb;
                float3 c1 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( px.x, 0)).rgb;
                float3 c2 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0, -px.y)).rgb;
                float3 c3 = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0,  px.y)).rgb;

                float e = abs(Luma(c0) - Luma(c1)) + abs(Luma(c2) - Luma(c3)); // 0..2-ish
                float m = saturate(1.0 - e * _EdgeAmount);
                return m;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv  = input.texcoord;
                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv) * _Tint;

                // Tone shaping on luma
                float g = pow(saturate(Luma(src.rgb)), _Gamma);
                g = saturate((g + _Lift) * _Gain);

                // Screen pixel coords
                int2 pixelXY = int2(floor(uv * _ScreenParams.xy));

                // Depth (optional)
                float depthMask = 1.0;
                float depth     = 1e6;
                if (_UseDepthMask > 0.5 || _UseDepthScale > 0.5)
                {
                    depth = SampleEyeDepth(uv);
                }
                if (_UseDepthMask > 0.5)
                {
                    float nearOn = _NearOn;
                    float farOff = max(_FarOff, nearOn + 0.001);
                    depthMask = saturate((farOff - depth) / (farOff - nearOn));
                }

                // Pattern scale by depth (optional)
                float depthScale = 1.0;
                if (_UseDepthScale > 0.5)
                {
                    float t = 0.0;
                    if (_FarOff > _NearOn)
                        t = saturate((depth - _NearOn) / (_FarOff - _NearOn));
                    depthScale = lerp(_ScaleNear, _ScaleFar, t);
                }

                float scaledPattern = _DitherScale * depthScale;

                // Temporal jitter (optional)
                float jitter = 0.0;
                if (_UseTemporal > 0.5)
                {
                    // Use _Time.y (seconds) – flip sign every ~0.5s-ish via sin
                    float s = sin(_Time.y * 6.2831853);    // 1Hz cycle
                    jitter = _TemporalAmount * 0.015625 * sign(s); // 1/64 ~= 0.015625
                }

                // Edge mask (optional)
                float edgeMask = (_UseEdgeMask > 0.5) ? EdgeMask(uv) : 1.0;

                // Threshold(s)
                float n  = saturate(DitherThreshold(pixelXY, scaledPattern) + jitter);

                float3 dithered;

                if (_UseQuantize > 0.5)
                {
                    // Quantized mode
                    float levels = max(2.0, _Levels);

                    if (_UseRGBChannels > 0.5)
                    {
                        // Per-channel offsets using fixed pixel offsets (decorrelate)
                        float nG = saturate(DitherThreshold(pixelXY + int2(3,1), scaledPattern) + jitter);
                        float nB = saturate(DitherThreshold(pixelXY + int2(1,4), scaledPattern) + jitter);

                        float3 q = floor(saturate(src.rgb) * levels + float3(n, nG, nB)) / (levels - 1.0);
                        dithered = q;
                    }
                    else
                    {
                        float q = floor(saturate(g) * levels + n) / (levels - 1.0);
                        dithered = q.xxx;
                    }
                }
                else
                {
                    // Binary mode
                    float on = step(n, g);
                    dithered = on.xxx;
                }

                // Final mix with masks
                float mixAmt = _DitherStrength * depthMask * edgeMask;
                float3 outRGB = lerp(src.rgb, dithered, mixAmt);

                return float4(outRGB, src.a);
            }
            ENDHLSL
        }
    }
}
