Shader "Custom/HalftoneDepth"
{
    Properties
    {
        // Look
        [KeywordEnum(Dots,Lines)] _Mode("Mode", Float) = 0
        _ScalePx("Cell Size (pixels)", Range(2,64)) = 12
        _AngleDeg("Screen Angle (deg)", Range(0,180)) = 45
        _Contrast("Contrast", Range(0,2)) = 1
        [Toggle] _Invert("Invert", Float) = 0

        // Color
        [KeywordEnum(InkOnBg,MultiplySrc)] _BlendMode("Blend", Float) = 0
        _InkColor("Ink Color", Color) = (0,0,0,1)
        _BgColor("Background Color", Color) = (1,1,1,1)
        _Tint("Final Tint", Color) = (1,1,1,1)

        // Depth fade
        [Toggle] _UseDepthFade("Fade By Depth", Float) = 1
        _NearFade("Near Start", Float) = 20
        _FarFade("Far End", Float) = 60
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "HalftoneDepthFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma shader_feature_local _MODE_DOTS _MODE_LINES
            #pragma shader_feature_local _BLENDMODE_INKONBG _BLENDMODE_MULTIPLYSRC
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);

            float _ScalePx, _AngleDeg, _Contrast, _Invert;
            float4 _InkColor, _BgColor, _Tint;
            float _UseDepthFade, _NearFade, _FarFade;

            inline float Luma709(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
            float2 rot2(float2 p, float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}

            // Sample linear eye-space depth
            float SampleLinearEyeDepth(float2 uv)
            {
                float raw = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
                return LinearEyeDepth(raw, _ZBufferParams);
            }

            float4 Frag(Varyings i) : SV_Target
            {
                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord).rgb;

                //---------------------------------
                // Depth fade to ignore far planes
                //---------------------------------
                float fade = 1.0;
                if (_UseDepthFade > 0.5)
                {
                    float d = SampleLinearEyeDepth(i.texcoord);
                    fade = saturate(1.0 - smoothstep(_NearFade, _FarFade, d));
                    if (fade <= 0.001)
                        return float4(src, 1); // early exit, skip effect on sky
                }

                //---------------------------------
                // Halftone tone & pattern
                //---------------------------------
                float L = saturate(Luma709(src));
                L = pow(L, max(1e-3, 1.0 / max(1e-3, _Contrast)));
                if (_Invert > 0.5) L = 1.0 - L;

                float2 texSize = _BlitTexture_TexelSize.zw;
                float2 ppx = i.texcoord * texSize;
                float ang = radians(_AngleDeg);
                float2 rp = rot2(ppx, ang);
                float2 cell = frac(rp / _ScalePx) - 0.5;
                float2 dpx = fwidth(rp / _ScalePx);
                float aa = 0.75 * max(dpx.x, dpx.y);

            #if defined(_MODE_DOTS)
                float radius = 0.5 * sqrt(1.0 - L);
                float dist = length(cell);
                float mark = 1.0 - smoothstep(radius - aa, radius + aa, dist);
            #else
                float halfW = 0.5 * (1.0 - L);
                float v = abs(cell.y);
                float mark = 1.0 - smoothstep(halfW - aa, halfW + aa, v);
            #endif

            #if defined(_BLENDMODE_INKONBG)
                float3 ink = _InkColor.rgb;
                float3 bg = _BgColor.rgb;
                float3 outC = lerp(bg, ink, mark);
            #else
                float3 outC = lerp(src, src * _InkColor.rgb, mark);
            #endif

                outC = lerp(src, outC, fade);
                return float4(outC, 1) * _Tint;
            }
            ENDHLSL
        }
    }
}
