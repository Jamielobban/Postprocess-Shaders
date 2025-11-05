Shader "Custom/Kaleidoscope"
{
    Properties{
        _Slices("Slice Count", Range(2,16)) = 6
        _Angle("Rotation Offset", Range(0,360)) = 0
    }
    SubShader{
        Tags{ "RenderPipeline"="UniversalPipeline" }
        Pass{
            Name "KaleidoscopeFullScreen"
            ZTest Always ZWrite Off Cull Off Blend One Zero
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Slices,_Angle;

            float2 Rot(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}
            float4 Frag(Varyings i):SV_Target{
                float2 uv=i.texcoord-0.5;
                float ang=atan2(uv.y,uv.x)+radians(_Angle);
                float r=length(uv);
                float seg=6.28318/_Slices;
                ang=fmod(abs(ang),seg);
                if(ang>seg*0.5) ang=seg-ang;
                float2 muv=float2(cos(ang),sin(ang))*r;
                float3 col=SAMPLE_TEXTURE2D_X(_BlitTexture,sampler_LinearClamp,muv+0.5).rgb;
                return float4(col,1);
            }
            ENDHLSL
        }
    }
}
