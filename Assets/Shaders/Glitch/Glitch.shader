Shader "Custom/BaseGlitch_RowBlocks"
{
    Properties
    {
        _Tint              ("Tint Color", Color) = (1,1,1,1)
        _GlitchAmount      ("Glitch Amount", Range(0,1)) = 0.6

        // Line jitter (kept)
        _LineJitterProb    ("Line Jitter Probability", Range(0,1)) = 0.5
        _LineJitterAmp     ("Line Jitter Amplitude (px)", Range(0,32)) = 6

        // Block UV jumps (row-gated)
        _BlockProb         ("Block Jump Probability", Range(0,1)) = 0.35
        _BlockSize         ("Block Size (pixels)", Range(2,128)) = 32
        _BlockShift        ("Block Shift (px)", Range(0,64)) = 12

        // NEW: row gating
        _RowProb           ("Row Active Probability", Range(0,1)) = 0.35
        _RowHeight         ("Row Height (px)", Range(2,128)) = 24
        _RowChangeRate     ("Row Shuffle Rate (Hz)", Range(0,30)) = 6

        // RGB split + scanline (kept)
        _ChromaAmount      ("RGB Split (px)", Range(0,8)) = 2
        _ScanlineAmount    ("Scanline Darken", Range(0,1)) = 0.2
        _ScanlineDensity   ("Scanline Density", Range(200,2000)) = 720

        // Frame stutter (kept)
        _StutterProb       ("Frame Hold Probability", Range(0,1)) = 0.12
        _StutterStrength   ("Frame Hold Strength", Range(0,1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalRenderPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullScreenGlitch_RowBlocks"
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

            float  _GlitchAmount;

            float  _LineJitterProb;
            float  _LineJitterAmp;

            float  _BlockProb;
            float  _BlockSize;
            float  _BlockShift;

            // Row gating
            float  _RowProb;
            float  _RowHeight;
            float  _RowChangeRate;

            float  _ChromaAmount;

            float  _ScanlineAmount;
            float  _ScanlineDensity;

            float  _StutterProb;
            float  _StutterStrength;

            // Hash helpers
            float Hash11(float x) {
                return frac(sin(x * 12.9898) * 43758.5453);
            }
            float Hash21(float2 p) {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
            }

            float2 Pixelate(float2 uv, float2 screenSize, float blockPx)
            {
                float2 px = uv * screenSize;
                px = floor(px / blockPx) * blockPx + 0.5;
                return px / screenSize;
            }

            float4 SampleSrc(float2 uv) { return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv); }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 screenSize = _ScreenParams.xy;
                float  t = _Time.y;

                // --- 1) Frame stutter (subtle)
                float stutterRnd = Hash11(floor(t * 60.0));
                float stutterMask = step(1.0 - _StutterProb * _GlitchAmount, stutterRnd);
                float stutterAmt = lerp(0.0, _StutterStrength * 0.003, stutterMask);
                uv.x += stutterAmt;

                // --- 2) Line jitter (per scanline)
                float lineIdx = floor(uv.y * screenSize.y);
                float lineRnd = Hash21(float2(lineIdx, floor(t * 24.0)));
                float lineDo  = step(1.0 - _LineJitterProb * _GlitchAmount, lineRnd);
                float lineAmpPx = _LineJitterAmp * _GlitchAmount;
                float lineShift = (lineDo > 0.5) ? ((Hash11(lineIdx + t*13.7) * 2.0 - 1.0) * lineAmpPx / screenSize.x) : 0.0;
                uv.x += lineShift;

                // --- 3) Row gating (decide which horizontal bands are active)
                float rowH = max(2.0, _RowHeight);
                float rowIndex = floor((uv.y * screenSize.y) / rowH);
                // Shuffle rows over time: change seed at _RowChangeRate Hz
                float rowSeedTime = floor(t * _RowChangeRate);
                float rowRnd = Hash21(float2(rowIndex, rowSeedTime));
                float rowActive = step(1.0 - _RowProb * _GlitchAmount, rowRnd); // 0 or 1

                // --- 4) Block UV jumps (applied only if rowActive==1)
                float2 uvForBlocks = uv;
                if (rowActive > 0.5)
                {
                    float blockPx = max(2.0, _BlockSize);
                    float2 blockUV = Pixelate(uvForBlocks, screenSize, blockPx);

                    float2 blockID = floor(blockUV * screenSize / blockPx);
                    float  blockRnd = Hash21(blockID + floor(t * 6.0));
                    float  blockDo  = step(1.0 - _BlockProb * _GlitchAmount, blockRnd);

                    float  blockShiftPx = _BlockShift * _GlitchAmount;
                    float2 blockShift = (blockDo > 0.5)
                        ? float2((Hash11(blockRnd + 1.23) * 2.0 - 1.0) * (blockShiftPx / screenSize.x), 0.0)
                        : float2(0.0, 0.0);

                    uvForBlocks = blockUV + blockShift;
                }

                // --- 5) RGB split on the (possibly shifted) UV
                float split = (_ChromaAmount * _GlitchAmount) / screenSize.x;
                float2 dir  = float2(1.0, 0.0);
                float2 uvR = uvForBlocks + dir * split;
                float2 uvG = uvForBlocks;
                float2 uvB = uvForBlocks - dir * split;

                float3 rgb;
                rgb.r = SampleSrc(saturate(uvR)).r;
                rgb.g = SampleSrc(saturate(uvG)).g;
                rgb.b = SampleSrc(saturate(uvB)).b;

                float4 col = float4(rgb, SampleSrc(saturate(uv)).a);

                // --- 6) Scanlines
                float scan = 1.0 - _ScanlineAmount * _GlitchAmount * 0.5 * (0.5 + 0.5 * cos(uv.y * _ScanlineDensity * 6.2831853));
                col.rgb *= scan;

                // Occasional line dropout
                float dropout = step(0.995, Hash21(float2(lineIdx, t * 5.1)));
                col.rgb *= (1.0 - dropout * 0.7 * _GlitchAmount);

                return col * _Tint;
            }
            ENDHLSL
        }
    }
}
