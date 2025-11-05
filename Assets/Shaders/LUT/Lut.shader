Shader "Custom/LumaLUT1D"
{
    Properties
    {
        _PaletteTex     ("Palette (1D strip)", 2D) = "white" {}
        _PaletteWidth   ("Palette Width (texels)", Float) = 128
        _RowIndex       ("Row Index (0=top)", Float) = 0     // 0 or 1 for 128x2; keep 0 for 128x1
        _Contribution   ("Contribution", Range(0,1)) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "RenderType"="Opaque" }
        Pass
        {
            Name "FullScreenLumaLUT1D"
            ZTest Always ZWrite Off Cull Off Blend One Zero

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"


            TEXTURE2D(_PaletteTex); SAMPLER(sampler_PaletteTex);
            float4 _PaletteTex_TexelSize; // (1/w, 1/h, w, h)
            float  _PaletteWidth;
            float  _RowIndex;
            float  _Contribution;

            float4 Frag(Varyings i) : SV_Target
            {
                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, i.texcoord).rgb;

                // Map by luminance (linear)
                float l = dot(src, float3(0.2126, 0.7152, 0.0722));
                l = saturate(l);

                // Horizontal 1D lookup: X = luma, Y = chosen row center
                float w = max(1.0, _PaletteTex_TexelSize.z); // actual width
                float h = max(1.0, _PaletteTex_TexelSize.w); // actual height

                // Use declared logical width for stable sampling even if imported size differs
                float x = (l * (_PaletteWidth - 1.0) + 0.5) / _PaletteWidth;

                // Pick row: for 128x1 use _RowIndex=0; for 128x2 use 0 (top) or 1 (bottom)
                float row = clamp(_RowIndex, 0.0, max(0.0, h - 1.0));
                float y   = (row + 0.5) / h;

                float3 mapped = SAMPLE_TEXTURE2D(_PaletteTex, sampler_PaletteTex, float2(x, y)).rgb;

                return float4(lerp(src, mapped, _Contribution), 1);
            }
            ENDHLSL
        }
    }
}
