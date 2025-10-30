using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
#if UNITY_6000_0_OR_NEWER
using UnityEngine.Rendering.RenderGraphModule;
#endif

// Simple, robust fullscreen blit for a Material/Pass.
// Works in Editor & Player, URP 12+ and Unity 6 (RenderGraph).
public class GlitchFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public Material material;       // assign your material that uses Shader "Custom/Glitch"
        public int passIndex = 0;       // 0 for your single-pass shader
        public RenderPassEvent injectionPoint = RenderPassEvent.BeforeRenderingPostProcessing;
        public bool showInSceneView = true;
        public bool forcePointFiltering = false;
    }
    public Settings settings = new();

    class Pass : ScriptableRenderPass
    {
        readonly Settings s;
        RTHandle tempColor;

        public Pass(Settings s)
        {
            this.s = s;
            profilingSampler = new ProfilingSampler("GlitchFeature");
            renderPassEvent = s.injectionPoint;
            // Tell URP/RenderGraph we read camera color so the pass isn't culled.
            ConfigureInput(ScriptableRenderPassInput.Color);
#if UNITY_6000_0_OR_NEWER
            requiresIntermediateTexture = true; // hint for non-RG fallback, OK to leave set
#endif
        }

        // Pre-6000 path (Execute) + non-RG fallback
#if UNITY_6000_0_OR_NEWER
        [System.Obsolete]
#endif
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData data)
        {
            var desc = data.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref tempColor, desc, name: "_GlitchTemp");
        }

#if UNITY_6000_0_OR_NEWER
        [System.Obsolete]
#endif
        public override void Execute(ScriptableRenderContext ctx, ref RenderingData data)
        {
            if (!s.material) return;
            if (data.cameraData.isPreviewCamera) return;
            if (data.cameraData.isSceneViewCamera && !s.showInSceneView) return;

            var cmd = CommandBufferPool.Get("GlitchFeature");
            using (new ProfilingScope(cmd, profilingSampler))
            {
                var src = data.cameraData.renderer.cameraColorTargetHandle;
                // source -> temp
                Blitter.BlitCameraTexture(cmd, src, tempColor, bilinear: !s.forcePointFiltering);
                // temp -> color with glitch material
                Blitter.BlitCameraTexture(cmd, tempColor, src, s.material, s.passIndex);
            }
            ctx.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }

#if UNITY_6000_0_OR_NEWER
        // Unity 6 RenderGraph path
        private class CopyData { public TextureHandle input; public bool bilinear; }
        private class MainData { public TextureHandle input; public Material mat; public int pass; }

        void RG_Copy(RasterCommandBuffer cmd, RTHandle src, bool bilinear)
        {
            Blitter.BlitTexture(cmd, src, new Vector4(1,1,0,0), 0f, bilinear);
        }
        void RG_Main(RasterCommandBuffer cmd, RTHandle src, Material mat, int pass)
        {
            Blitter.BlitTexture(cmd, src, new Vector4(1,1,0,0), mat, pass);
        }

        public override void RecordRenderGraph(RenderGraph rg, ContextContainer frame)
        {
            if (!s.material) return;

            var res = frame.Get<UniversalResourceData>();
            var cam = frame.Get<UniversalCameraData>();

            if (cam.isPreviewCamera) return;
            if (cam.isSceneViewCamera && !s.showInSceneView) return;

            // Allocate temp color (same size as activeColor)
            var desc = cam.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;
            var tempTex = UniversalRenderer.CreateRenderGraphTexture(rg, desc, "_GlitchTemp", false);

            Debug.Log("[GlitchFeature] Recording RG passes (scene=" + UnityEngine.SceneManagement.SceneManager.GetActiveScene().name + ")");
            
            // Copy: activeColor -> temp
            using (var builder = rg.AddRasterRenderPass<CopyData>("Glitch_CopyColor", out var data, profilingSampler))
            {
                data.input = res.activeColorTexture;
                data.bilinear = !s.forcePointFiltering;

                builder.UseTexture(res.activeColorTexture, AccessFlags.Read);
                builder.SetRenderAttachment(tempTex, 0, AccessFlags.Write);
                builder.SetRenderFunc((CopyData d, RasterGraphContext ctx) => RG_Copy(ctx.cmd, d.input, d.bilinear));
            }

            // Main: temp -> activeColor using material
            using (var builder = rg.AddRasterRenderPass<MainData>("Glitch_Main", out var data, profilingSampler))
            {
                data.input = tempTex;
                data.mat = s.material;
                data.pass = s.passIndex;

                builder.UseTexture(tempTex, AccessFlags.Read);
                builder.SetRenderAttachment(res.activeColorTexture, 0, AccessFlags.Write);
                builder.SetRenderFunc((MainData d, RasterGraphContext ctx) => RG_Main(ctx.cmd, d.input, d.mat, d.pass));
            }
        }
#endif
    }

    Pass pass;

    public override void Create()
    {
        pass = new Pass(settings);
        name = "GlitchFeature";
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData rd)
    {

        Debug.Log("[GlitchFeature] AddRenderPasses executed on: " + rd.cameraData.camera.name);

        // Optional: gate by scene/preview if you want at feature level
        renderer.EnqueuePass(pass);
    }
}
