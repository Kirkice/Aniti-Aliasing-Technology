using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class FastApproximateAntiAliasingFeature : ScriptableRendererFeature
{
    public enum FxAAType
    {
        Quality,
        Console
    }
    [System.Serializable]
    public class Settings
    {
        public FxAAType type = FxAAType.Quality;
        [Range(0.01f, 0.5f)] public float AbsoluteLumaThreshold = 0.1f;
        [Range(0.01f, 0.5f)] public float RelativeLumaThreshold = 0.1f;
        [Range(0.1f, 10.0f)] public float SubpixelBlending = 0.75f;
    }

    class FastApproximateAntiAliasingPass : ScriptableRenderPass
    {
        static readonly string k_RenderTag = "Fast Approximate AntiAliasing Pass";
        private Material material;
        private ScriptableRenderer _renderer;
        private Settings settings;

        public FastApproximateAntiAliasingPass(Settings settings)
        {
            this.settings = settings;
            material = CoreUtils.CreateEngineMaterial(Shader.Find("FxAA"));
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (material == null)
                return;

            if (renderingData.cameraData.cameraType != CameraType.Game)
                return;

            var cmd = CommandBufferPool.Get(k_RenderTag);
            Render(cmd, ref renderingData);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        void Render(CommandBuffer cmd, ref RenderingData renderingData)
        {
            int passID = settings.type == FxAAType.Quality ? 0 : 1;
            var source = _renderer.cameraColorTarget;
            RenderTextureDescriptor opaqueDesc = renderingData.cameraData.cameraTargetDescriptor;
            opaqueDesc.depthBufferBits = 0;

            var w = renderingData.cameraData.camera.pixelWidth;
            var h = renderingData.cameraData.camera.pixelHeight;
            
            RenderTexture temp = RenderTexture.GetTemporary(w, h, 0, RenderTextureFormat.DefaultHDR);
            material.SetVector("_FxAA_Params", new Vector4(settings.AbsoluteLumaThreshold, settings.RelativeLumaThreshold, settings.SubpixelBlending, 1));
            Blit(cmd, source, temp, material,passID);
            Blit(cmd, temp, source);
            RenderTexture.ReleaseTemporary(temp);
        }

        public void Setup(ScriptableRenderer renderer, RenderTargetHandle dest)
        {
            this._renderer = renderer;
        }

        public override void FrameCleanup(CommandBuffer cmd)
        {
        }
    }

    FastApproximateAntiAliasingPass m_FastApproximateAntiAliasingPass;
    public Settings mSettings;

    /// <inheritdoc/>
    public override void Create()
    {
        m_FastApproximateAntiAliasingPass = new FastApproximateAntiAliasingPass(mSettings);
        m_FastApproximateAntiAliasingPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }


    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var dest = RenderTargetHandle.CameraTarget;
        m_FastApproximateAntiAliasingPass.Setup(renderer, dest);
        renderer.EnqueuePass(m_FastApproximateAntiAliasingPass);
    }
}