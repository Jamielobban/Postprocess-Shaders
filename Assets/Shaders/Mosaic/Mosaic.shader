Shader "Custom/BaseMosaic_Overlay"
{
    Properties
    {
        _Tint            ("Tint Color", Color) = (1,1,1,1)

        // Mosaic / pixelation
        _PixelSizeXY     ("Pixel Size (px X,Y)", Vector) = (8,8,0,0)
        [Toggle] _KeepSquare ("Keep Square Pixels", Float) = 1

        // Overlay (tileable grid/lines texture)
        _OverlayTex      ("Overlay Texture (tileable)", 2D) = "white" {}
        _OverlayTint     ("Overlay Tint", Color) = (1,1,1,1)
        _OverlayOpacity  ("Overlay Opacity", Range(0,1)) = 1
        [Toggle] _OverlayPerCell ("Overlay Per Mosaic Cell", Float) = 1
        _OverlayRepeat   ("Per-Cell Overlay Repeat (u,v)", Vector) = (1,1,0,0)
        _OverlayGlobalScale ("Global Overlay Scale (u,v)", Vector) = (8,8,0,0) // if not per cell
        _OverlayOffset   ("Overlay UV Offset (u,v)", Vector) = (0,0,0,0)
        [Toggle] _OverlayMultiply ("Multiply Blend (else alpha over)", Float) = 0
        [Toggle] _OverlayUsePoint ("Point Filter (crisp)", Float) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalRenderPipeline" "Queue"="Transparent" "RenderType"="Opaque" }

        Pass
        {
            Name "FullScreenMosaicOverlay"
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

            float4 _PixelSizeXY;
            float  _KeepSquare;

            TEXTURE2D(_OverlayTex);
            SAMPLER(sampler_OverlayTex);
            // Optional point sampler for crisp lines
            #if defined(UNITY_DOTS_INSTANCED_PROP)
            #endif
            // URP gives us sampler_LinearClamp; we can fake point sampling by snapping UVs to texel centers when _OverlayUsePoint > 0.5
            float  _OverlayOpacity;
            float4 _OverlayTint;
            float  _OverlayPerCell;
            float4 _OverlayRepeat;
            float4 _OverlayGlobalScale;
            float4 _OverlayOffset;
            float  _OverlayMultiply;
            float  _OverlayUsePoint;

            // Helper: snap UVs to nearest texel center (for crisp overlay)
            float2 SnapToTexel(float2 uv, float2 texSize)
            {
                return (floor(uv * texSize) + 0.5) / texSize;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                // --- Mosaic sampling ---
                float2 uv = input.texcoord;
                float2 screenSize = _ScreenParams.xy;
                float2 px = max(_PixelSizeXY.xy, float2(1.0, 1.0));
                if (_KeepSquare > 0.5) px.y = px.x;

                float2 cells = screenSize / px;                          // number of mosaic cells
                float2 uvBlock = (floor(uv * cells) + 0.5) / cells;      // center of each cell
                float4 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uvBlock);
                float4 col = src;

                // --- Overlay UVs ---
                float2 oUV;
                if (_OverlayPerCell > 0.5)
                {
                    // Repeat overlay inside each mosaic cell (so grid aligns to block boundaries)
                    float2 cellUV = frac(uv * cells); // 0..1 within current cell
                    oUV = cellUV * _OverlayRepeat.xy + _OverlayOffset.xy;
                }
                else
                {
                    // Global overlay tiling independent of mosaic
                    oUV = uv * _OverlayGlobalScale.xy + _OverlayOffset.xy;
                }

                // Optional point sampling for crisp 1px lines (avoids blur)
                float4 overlaySample;
                {
                    // Need texture size; approximate via _ScreenParams if unknown.
                    // Better: set your overlay texture import size (e.g., 512x512) and pass via material if needed.
                    // Here we do linear sample by default; optional pseudo-point:
                    float2 uvSample = frac(oUV);
                    if (_OverlayUsePoint > 0.5)
                    {
                        // Assume typical 512x512 overlay; change if needed via _OverlayGlobalScale to keep sharp.
                        // If your overlay is different size, replace 512.0 with your actual texture size or add a property.
                        float2 approxTexSize = float2(512.0, 512.0);
                        uvSample = SnapToTexel(uvSample, approxTexSize);
                    }
                    overlaySample = SAMPLE_TEXTURE2D(_OverlayTex, sampler_OverlayTex, uvSample);
                }

                // Tint + opacity
                float4 overlayCol = overlaySample * _OverlayTint;
                float  a = saturate(overlayCol.a * _OverlayOpacity);

                // Blend
                if (_OverlayMultiply > 0.5)
                {
                    col.rgb = lerp(col.rgb, col.rgb * overlayCol.rgb, a);
                }
                else
                {
                    col.rgb = lerp(col.rgb, overlayCol.rgb, a);
                }

                return col * _Tint;
            }
            ENDHLSL
        }
    }
}
