using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class MorphologicalAntialiasingFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        [Range(1.0f, 300.0f)] public float EdgeDetectionThreshold = 12.0f;
    }

    class MorphologicalAntialiasingPass : ScriptableRenderPass
    {
        static readonly string k_RenderTag = "Morphological Antialiasing Pass";
        private Material material;
        private ScriptableRenderer _renderer;
        private Settings settings;

        public MorphologicalAntialiasingPass(Settings settings)
        {
            material = CoreUtils.CreateEngineMaterial(Shader.Find("MLAA"));
            this.settings = settings;
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
            var source = _renderer.cameraColorTarget;
            RenderTextureDescriptor opaqueDesc = renderingData.cameraData.cameraTargetDescriptor;
            opaqueDesc.depthBufferBits = 0;

            var w = renderingData.cameraData.camera.pixelWidth;
            var h = renderingData.cameraData.camera.pixelHeight;
            
            RenderTexture edgeTex = RenderTexture.GetTemporary(w, h, 0, RenderTextureFormat.DefaultHDR);
            RenderTexture edgeCountTex = RenderTexture.GetTemporary(w, h, 0, RenderTextureFormat.DefaultHDR);

            material.SetVector("gParam", new Vector4(0, 0, 1 / settings.EdgeDetectionThreshold, 0));
            Blit(cmd, source, edgeTex, material,0);
            material.SetTexture("_EdgeMaskTex",edgeTex);
            Blit(cmd, source, edgeCountTex, material,1);
            Blit(cmd, source, edgeTex);
            
            material.SetTexture("_EdgeCountTex",edgeCountTex);
            Blit(cmd, edgeTex, source,material,2);
            
            RenderTexture.ReleaseTemporary(edgeTex);
            RenderTexture.ReleaseTemporary(edgeCountTex);
        }

        public void Setup(ScriptableRenderer renderer, RenderTargetHandle dest)
        {
            this._renderer = renderer;
        }

        public override void FrameCleanup(CommandBuffer cmd)
        {
        }
    }

    MorphologicalAntialiasingPass m_MorphologicalAntialiasingPass;
    public Settings mSettings;

    /// <inheritdoc/>
    public override void Create()
    {
        m_MorphologicalAntialiasingPass = new MorphologicalAntialiasingPass(mSettings);
        m_MorphologicalAntialiasingPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }


    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var dest = RenderTargetHandle.CameraTarget;
        m_MorphologicalAntialiasingPass.Setup(renderer, dest);
        renderer.EnqueuePass(m_MorphologicalAntialiasingPass);
    }
}