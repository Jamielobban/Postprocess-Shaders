Shader "Custom/HeatHaze"
{
    Properties{
        _Strength("Distortion (px)", Range(0,8)) = 2
        _Frequency("Noise Freq", Range(0.1,10)) = 3
        _Speed("Scroll Speed", Range(0,5)) = 1.2
        _Aniso("Anisotropy (0..1)", Range(0,1)) = 0.6
        _Blend("Mix With Original", Range(0,1)) = 1
    }
    SubShader{
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass{
            Name "HeatHazeFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Strength,_Frequency,_Speed,_Aniso,_Blend;
            float hash21(float2 p){ return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
            float noise(float2 p){
                float2 i=floor(p), f=frac(p);
                float2 u=f*f*(3.0-2.0*f);
                float a=hash21(i+float2(0,0));
                float b=hash21(i+float2(1,0));
                float c=hash21(i+float2(0,1));
                float d=hash21(i+float2(1,1));
                return lerp(lerp(a,b,u.x),lerp(c,d,u.x),u.y);
            }
            float4 Frag(Varyings i):SV_Target{
                float2 uv=i.texcoord;
                float2 px=_BlitTexture_TexelSize.xy;
                float t=_Time.y*_Speed;
                float2 dir=normalize(float2(1,0.2));
                float2 uvn=uv*_Frequency+dir*t;
                float n=noise(uvn);
                n+=0.5*noise(uvn*2.0+7.3);
                n+=0.25*noise(uvn*4.0+2.1);
                float2 offs=float2((n-0.5)*_Strength*px.x,(n-0.5)*_Strength*px.y*(1.0-_Aniso));
                float3 c0=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv).rgb;
                float3 c1=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,uv+offs).rgb;
                return float4(lerp(c0,c1,_Blend),1);
            }
            ENDHLSL
        }
    }
}
