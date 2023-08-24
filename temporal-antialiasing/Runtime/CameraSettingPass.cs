namespace UnityEngine.Rendering.Universal.Internal
{
    internal sealed class TAAData 
    {
        #region Fields
        internal Vector2 sampleOffset;
        internal Matrix4x4 projOverride;
        internal Matrix4x4 porjPreview;
        internal Matrix4x4 viewPreview;
        #endregion
        #region Constructors
        internal TAAData()
        {
            projOverride = Matrix4x4.identity;
            porjPreview = Matrix4x4.identity;
            viewPreview = Matrix4x4.identity;
        }
        #endregion
    }
    
    public class CameraSettingPass : ScriptableRenderPass
    {
        ProfilingSampler m_ProfilingSampler;
        string m_ProfilerTag = "SetCamera(TAA)";
        TAAData m_TaaData;
        internal CameraSettingPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingOpaques + 1;
        }

        internal void Setup(TAAData data)
        {
            m_TaaData = data;
        }

        /// <inheritdoc/>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);
            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CameraData cameraData = renderingData.cameraData;
                cmd.SetViewProjectionMatrices(cameraData.camera.worldToCameraMatrix, m_TaaData.projOverride);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

}