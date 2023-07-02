namespace UnityEngine.Rendering.Universal.Internal
{
    internal static class TAAShaderKeywordStrings
    {
        internal static readonly string HighTAAQuality = "_HIGH_TAA";
        internal static readonly string MiddleTAAQuality = "_MIDDLE_TAA";
        internal static readonly string LOWTAAQuality = "_LOW_TAA";
    }
        
    internal static class TAAShaderConstants
    {
        public static readonly int _TAA_Params = Shader.PropertyToID("_TAA_Params");
        public static readonly int _TAA_pre_texture = Shader.PropertyToID("_TAA_Pretexture");
        public static readonly int _TAA_pre_vp = Shader.PropertyToID("_TAA_Pretexture");
        public static readonly int _TAA_PrevViewProjM = Shader.PropertyToID("_PrevViewProjM_TAA");
        public static readonly int _TAA_CurInvView = Shader.PropertyToID("_I_V_Current_jittered");
        public static readonly int _TAA_CurInvProj = Shader.PropertyToID("_I_P_Current_jittered");
    }
    
    public class TemporalAntiAliasingPass : ScriptableRenderPass
    {
        RenderTexture[] historyBuffer;
        static int indexWrite = 0;
        TAAData m_TaaData;
        TemporalAntiAliasingFeature.Settings settings;
        Material m_Material;
        ProfilingSampler m_ProfilingSampler;
        ScriptableRenderer _renderer;
        string m_ProfilerTag = "TemporalAntiAliasing Pass";
        
        public TemporalAntiAliasingPass(Material mat)
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            m_Material = mat;
        }
        
        internal void Setup(ScriptableRenderer renderer, TAAData TaaData,TemporalAntiAliasingFeature.Settings settings)
        {
            // Set data
            m_TaaData = TaaData;
            this.settings = settings;
            this._renderer = renderer;
        }
        
        void ClearRT(ref RenderTexture rt)
        {
            if(rt!= null)
            {
                RenderTexture.ReleaseTemporary(rt);
                rt = null;
            }
        }
        
        internal void Clear()
        {
            if(historyBuffer!=null)
            {
                ClearRT(ref historyBuffer[0]);
                ClearRT(ref historyBuffer[1]);
                historyBuffer = null;
            }
        }
        
        void EnsureArray<T>(ref T[] array, int size, T initialValue = default(T))
        {
            if (array == null || array.Length != size)
            {
                array = new T[size];
                for (int i = 0; i != size; i++)
                    array[i] = initialValue;
            }
        }
        
        
        bool EnsureRenderTarget(ref RenderTexture rt, int width, int height, RenderTextureFormat format, FilterMode filterMode, int depthBits = 0, int antiAliasing = 1)
        {
            if (rt != null && (rt.width != width || rt.height != height || rt.format != format || rt.filterMode != filterMode || rt.antiAliasing != antiAliasing))
            {
                RenderTexture.ReleaseTemporary(rt);
                rt = null;
            }
            if (rt == null)
            {
                rt = RenderTexture.GetTemporary(width, height, depthBits, format, RenderTextureReadWrite.Default, antiAliasing);
                rt.filterMode = filterMode;
                rt.wrapMode = TextureWrapMode.Clamp;
                return true;// new target
            }
            return false;// same target
        }
        
        void DoTemporalAntiAliasing(CameraData cameraData, CommandBuffer cmd)
        {
            var source = _renderer.cameraColorTarget;
            var camera = cameraData.camera;

            if(m_Material==null)
                return;
            
            var descriptor = new RenderTextureDescriptor(camera.scaledPixelWidth, camera.scaledPixelHeight, RenderTextureFormat.DefaultHDR, 16);
            EnsureArray(ref historyBuffer, 2);
            EnsureRenderTarget(ref historyBuffer[0], descriptor.width, descriptor.height, descriptor.colorFormat, FilterMode.Bilinear);
            EnsureRenderTarget(ref historyBuffer[1], descriptor.width, descriptor.height, descriptor.colorFormat, FilterMode.Bilinear);

            int indexRead = indexWrite;
            indexWrite = (++indexWrite) % 2;
            
            Matrix4x4 inv_p_jitterd = Matrix4x4.Inverse(m_TaaData.projOverride);
            Matrix4x4 inv_v_jitterd = Matrix4x4.Inverse(camera.worldToCameraMatrix);
            Matrix4x4 previous_vp = m_TaaData.porjPreview * m_TaaData.viewPreview;
            m_Material.SetMatrix(TAAShaderConstants._TAA_CurInvView, inv_v_jitterd);
            m_Material.SetMatrix(TAAShaderConstants._TAA_CurInvProj, inv_p_jitterd);
            m_Material.SetMatrix(TAAShaderConstants._TAA_PrevViewProjM, previous_vp);
            m_Material.SetVector(TAAShaderConstants._TAA_Params, new Vector3(m_TaaData.sampleOffset.x, m_TaaData.sampleOffset.y, settings.feedback));
            m_Material.SetTexture(TAAShaderConstants._TAA_pre_texture, historyBuffer[indexRead]);
            CoreUtils.SetKeyword(cmd, TAAShaderKeywordStrings.HighTAAQuality, settings.AAQuality == AntialiasingQuality.High);
            CoreUtils.SetKeyword(cmd, TAAShaderKeywordStrings.MiddleTAAQuality, settings.AAQuality == AntialiasingQuality.Medium);
            CoreUtils.SetKeyword(cmd, TAAShaderKeywordStrings.LOWTAAQuality, settings.AAQuality == AntialiasingQuality.Low);
            cmd.Blit(source, historyBuffer[indexWrite], m_Material);
            cmd.Blit(historyBuffer[indexWrite], source);
        }
        
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);
            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                DoTemporalAntiAliasing(renderingData.cameraData, cmd);
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        void ExecuteCommand(ScriptableRenderContext context, CommandBuffer cmd)
        {
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
        }
        
    }   
}
