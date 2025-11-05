Shader "Custom/PaintingURP_Fullscreen"
{
    Properties
    {
        // Kept for UI compatibility; source actually comes from the renderer feature
        _MainTex ("Texture (unused, uses Camera Color)", 2D) = "white" {}
        
        [Toggle] _EnableEffect ("Enable Effect", Float) = 1
        _KernelSize ("Kernel Size (odd)", Int) = 17
        
        // Mode = 0: Rotated Quadrants, 1: Circular Sectors
        _RegionMode ("Region Mode (0=RotQuad,1=Sectors)", Int) = 0
        
        // Rotated Quadrants
        _RotationDegrees ("Quadrant Rotation (deg)", Range(0,180)) = 45
        
        // Circular Sectors
        _Sectors ("Sector Count (4 or 6)", Int) = 4
        [Toggle] _UseDiskKernel ("Use Circular Kernel", Float) = 1
    }
    
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "RenderType"="Opaque" }
        
        Pass
        {
            Name "PaintingFullScreen"
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One Zero
            
            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            // Fullscreen blit source from the Renderer Feature
            #define UNITY_PI 3.14159


            // Exposed params (names kept the same)
            float _EnableEffect;
            int   _KernelSize;
            int   _RegionMode;
            float _RotationDegrees;
            int   _Sectors;
            float _UseDiskKernel;

            struct Acc { float3 sum; float3 sq; int n; };

            float2x2 rot2(float a)
            {
                float s = sin(a), c = cos(a);
                return float2x2(c,-s, s,c);
            }

            void MeanVar(in Acc a, out float3 mean, out float varScalar)
            {
                float inv = 1.0 / max(a.n, 1);
                mean = a.sum * inv;
                float3 v3 = abs(a.sq * inv - mean * mean);
                varScalar = length(v3);
            }

            // Helper to sample camera color
            float3 SampleSrc(float2 uv)
            {
                return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                // Early out: no effect
                if (_EnableEffect < 0.5)
                {
                    return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.texcoord);
                }

                // Ensure odd kernel size (>=3)
                int N = max((_KernelSize | 1), 3);
                int half = (N - 1) / 2;

                float2 texel = _BlitTexture_TexelSize.xy;
                float2 uvMin = 0.5 * texel;
                float2 uvMax = 1.0 - uvMin;

                float3 outCol = 0;

                if (_RegionMode == 0)
                {
                    // --- Mode 0: Rotated Quadrants ---
                    Acc A = (Acc)0, B = (Acc)0, C = (Acc)0, D = (Acc)0;
                    float2x2 R = rot2(radians(_RotationDegrees));

                    [loop] for (int x = -half; x <= half; ++x)
                    {
                        [loop] for (int y = -half; y <= half; ++y)
                        {
                            float2 off = float2(x, y);
                            float2 pr  = mul(R, off); // rotated for binning only

                            float2 uv = clamp(input.texcoord + off * texel, uvMin, uvMax);
                            float3 c  = SampleSrc(uv);

                            // bin by sign in rotated frame (four quadrants)
                            if (pr.x <= 0 && pr.y <= 0) { A.sum+=c; A.sq+=c*c; A.n++; } // BL
                            if (pr.x >= 0 && pr.y <= 0) { B.sum+=c; B.sq+=c*c; B.n++; } // BR
                            if (pr.x <= 0 && pr.y >= 0) { C.sum+=c; C.sq+=c*c; C.n++; } // TL
                            if (pr.x >= 0 && pr.y >= 0) { D.sum+=c; D.sq+=c*c; D.n++; } // TR
                        }
                    }

                    float3 mA,mB,mC,mD; float vA,vB,vC,vD;
                    MeanVar(A, mA, vA);
                    MeanVar(B, mB, vB);
                    MeanVar(C, mC, vC);
                    MeanVar(D, mD, vD);

                    outCol = mA; float minV = vA;
                    if (vB < minV) { minV = vB; outCol = mB; }
                    if (vC < minV) { minV = vC; outCol = mC; }
                    if (vD < minV) { /*minV = vD;*/ outCol = mD; }
                }
                else
                {
                    // --- Mode 1: Circular Sectors (4 or 6) ---
                    int S = clamp(_Sectors, 4, 6);
                    float sectorSize = 2.0 * UNITY_PI / S;

                    Acc acc0=(Acc)0, acc1=(Acc)0, acc2=(Acc)0, acc3=(Acc)0, acc4=(Acc)0, acc5=(Acc)0;

                    [loop] for (int x = -half; x <= half; ++x)
                    {
                        [loop] for (int y = -half; y <= half; ++y)
                        {
                            float2 off = float2(x, y);

                            if (_UseDiskKernel > 0.5 && length(off) > half)
                                continue; // optional circular kernel

                            float2 uv = clamp(input.texcoord + off * texel, uvMin, uvMax);
                            float3 c  = SampleSrc(uv);

                            // angle in [0, 2pi)
                            float a = atan2(off.y, off.x);
                            a = (a < 0) ? a + 2.0 * UNITY_PI : a;

                            int idx = (int)floor(a / sectorSize);
                            idx = clamp(idx, 0, S - 1);

                            // accumulate
                            if (idx == 0) { acc0.sum+=c; acc0.sq+=c*c; acc0.n++; }
                            else if (idx == 1) { acc1.sum+=c; acc1.sq+=c*c; acc1.n++; }
                            else if (idx == 2) { acc2.sum+=c; acc2.sq+=c*c; acc2.n++; }
                            else if (idx == 3) { acc3.sum+=c; acc3.sq+=c*c; acc3.n++; }
                            else if (idx == 4) { acc4.sum+=c; acc4.sq+=c*c; acc4.n++; }
                            else              { acc5.sum+=c; acc5.sq+=c*c; acc5.n++; }
                        }
                    }

                    // evaluate and pick lowest-variance mean
                    float3 bestM = 0; float bestV = 1e9;
                    float3 m; float v;

                    if (S >= 1) { MeanVar(acc0, m, v); if (v < bestV) { bestV = v; bestM = m; } }
                    if (S >= 2) { MeanVar(acc1, m, v); if (v < bestV) { bestV = v; bestM = m; } }
                    if (S >= 3) { MeanVar(acc2, m, v); if (v < bestV) { bestV = v; bestM = m; } }
                    if (S >= 4) { MeanVar(acc3, m, v); if (v < bestV) { bestV = v; bestM = m; } }
                    if (S >= 5) { MeanVar(acc4, m, v); if (v < bestV) { bestV = v; bestM = m; } }
                    if (S >= 6) { MeanVar(acc5, m, v); if (v < bestV) { bestV = v; bestM = m; } }

                    outCol = bestM;
                }

                return float4(outCol, 1);
            }
            ENDHLSL
        }
    }
}
