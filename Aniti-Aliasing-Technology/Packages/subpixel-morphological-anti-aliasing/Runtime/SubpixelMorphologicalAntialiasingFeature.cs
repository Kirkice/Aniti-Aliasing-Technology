using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SubpixelMorphologicalAntialiasingFeature : ScriptableRendererFeature
{
	[System.Serializable]
	public class Settings
	{
		/// <summary>
		/// Render target mode. Keep it to <see cref="HDRMode.Auto"/> unless you know what you're doing.
		/// </summary>
		public HDRMode Hdr = HDRMode.Auto;

		/// <summary>
		/// Use this to fine tune your settings when working in Custom quality mode.
		/// </summary>
		/// <seealso cref="DebugPass"/>
		public DebugPass DebugPass = DebugPass.Off;

		/// <summary>
		/// Quality preset to use. Set to <see cref="QualityPreset.Custom"/> to fine tune every setting.
		/// </summary>
		/// <seealso cref="QualityPreset"/>
		public QualityPreset Quality = QualityPreset.High;

		/// <summary>
		/// You have three edge detection methods to choose from: luma, color or depth.
		/// They represent different quality/performance and anti-aliasing/sharpness tradeoffs, so our recommendation is
		/// for you to choose the one that best suits your particular scenario.
		/// </summary>
		/// <seealso cref="EdgeDetectionMethod"/>
		public EdgeDetectionMethod DetectionMethod = EdgeDetectionMethod.Luma;

		/// <summary>
		/// Predicated thresholding allows to better preserve texture details and to improve performance, by decreasing
		/// the number of detected edges using an additional buffer (the detph buffer).
		/// 
		/// It locally decreases the luma or color threshold if an edge is found in an additional buffer (so the global
		/// threshold can be higher).
		/// </summary>
		public bool UsePredication = false; // Unused with EdgeDetectionMethod.Depth

		/// <summary>
		/// Holds the custom preset to use with <see cref="QualityPreset.Custom"/>.
		/// </summary>
		public Preset CustomPreset;

		/// <summary>
		/// Holds the custom preset to use when <see cref="SMAA.UsePredication"/> is enabled.
		/// </summary>
		public PredicationPreset CustomPredicationPreset;

		/// <summary>
		/// This texture allows to obtain the area for a certain pattern and distances to the left and to right of the
		/// line. Automatically set by the component if <c>null</c>.
		/// </summary>
		public Texture2D AreaTex;

		/// <summary>
		/// This texture allows to know how many pixels we must advance in the last step of our line search algorithm,
		/// with a single fetch. Automatically set by the component if <c>null</c>.
		/// </summary>
		public Texture2D SearchTex;
	}
	
	class SubpixelMorphologicalAntialiasingPass : ScriptableRenderPass
	{
		static readonly string k_RenderTag = "Subpixel Morphological Antialiasing Pass";
		protected Preset[] m_StdPresets;
		private Material material;
		private ScriptableRenderer _renderer;
		private Settings settings;

		public SubpixelMorphologicalAntialiasingPass(Settings settings)
		{
			material = CoreUtils.CreateEngineMaterial(Shader.Find("SMAA"));
			this.settings = settings;
		}

		public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
		{
			if (material == null)
				return;
			
			if (settings.AreaTex == null || settings.SearchTex == null)
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
			
			var w = renderingData.cameraData.camera.pixelWidth;
			var h = renderingData.cameraData.camera.pixelHeight;
			Preset preset = settings.CustomPreset;
			
			if (settings.Quality != QualityPreset.Custom)
				preset = m_StdPresets[(int)settings.Quality];

			// Pass IDs
			int passEdgeDetection = (int)settings.DetectionMethod;
			int passBlendWeights = 4;
			int passNeighborhoodBlending = 5;

			// Render format
			RenderTextureFormat renderFormat = RenderTextureFormat.DefaultHDR;

			if (settings.Hdr == HDRMode.Off)
				renderFormat = RenderTextureFormat.Default;
			else if (settings.Hdr == HDRMode.On)
				renderFormat = RenderTextureFormat.DefaultHDR;
			
			// Uniforms
			material.SetTexture("_AreaTex", settings.AreaTex);
			material.SetTexture("_SearchTex", settings.SearchTex);

			material.SetVector("_Metrics", new Vector4(1f / (float)w, 1f / (float)h, w, h));
			material.SetVector("_Params1", new Vector4(preset.Threshold, preset.DepthThreshold, preset.MaxSearchSteps, preset.MaxSearchStepsDiag));
			material.SetVector("_Params2", new Vector2(preset.CornerRounding, preset.LocalContrastAdaptationFactor));

			// Handle predication & depth-based edge detection
			Shader.DisableKeyword("USE_PREDICATION");

			if (settings.UsePredication)
			{
				Shader.EnableKeyword("USE_PREDICATION");
				material.SetVector("_Params3", new Vector3(settings.CustomPredicationPreset.Threshold, settings.CustomPredicationPreset.Scale, settings.CustomPredicationPreset.Strength));
			}

			// Diag search & corner detection
			Shader.DisableKeyword("USE_DIAG_SEARCH");
			Shader.DisableKeyword("USE_CORNER_DETECTION");
			
			// Temporary render textures
			RenderTexture rt1 = RenderTexture.GetTemporary(w, h, 0,renderFormat);
			RenderTexture rt2 = RenderTexture.GetTemporary(w, h, 0, renderFormat);
			

			// Edge Detection
			cmd.Blit(source, rt1, material, passEdgeDetection);

			if (settings.DebugPass == DebugPass.Edges)
			{
				cmd.Blit(rt1, source);
			}
			else
			{
				// Blend Weights
				cmd.Blit(rt1, rt2, material, passBlendWeights);

				if (settings.DebugPass == DebugPass.Weights)
				{
					cmd.Blit(rt2, source);
				}
				else
				{
					// Neighborhood Blending
					material.SetTexture("_BlendTex", rt2);
					cmd.Blit(source, source, material, passNeighborhoodBlending);
				}
			}

			// Cleanup
			RenderTexture.ReleaseTemporary(rt1);
			RenderTexture.ReleaseTemporary(rt2);
		}

		public void Setup(ScriptableRenderer renderer, RenderTargetHandle dest)
		{
			this._renderer = renderer;
			CreatePresets();
		}

		public override void FrameCleanup(CommandBuffer cmd)
		{
		}
		
		void CreatePresets()
		{
			m_StdPresets = new Preset[4];

			// Low
			m_StdPresets[0] = new Preset
			{
				Threshold = 0.15f,
				MaxSearchSteps = 4
			};
			m_StdPresets[0].DiagDetection = false; // Can't use object initializer for bool (weird mono bug ?)
			m_StdPresets[0].CornerDetection = false;

			// Medium
			m_StdPresets[1] = new Preset
			{
				Threshold = 0.1f,
				MaxSearchSteps = 8
			};
			m_StdPresets[1].DiagDetection = false;
			m_StdPresets[1].CornerDetection = false;

			// High
			m_StdPresets[2] = new Preset
			{
				Threshold = 0.1f,
				MaxSearchSteps = 16,
				MaxSearchStepsDiag = 8,
				CornerRounding = 25
			};

			// Ultra
			m_StdPresets[3] = new Preset
			{
				Threshold = 0.05f,
				MaxSearchSteps = 32,
				MaxSearchStepsDiag = 16,
				CornerRounding = 25
			};
		}
	}
	
	SubpixelMorphologicalAntialiasingPass m_SubpixelMorphologicalAntialiasingPass;
    public Settings mSettings;

    /// <inheritdoc/>
    public override void Create()
    {
	    m_SubpixelMorphologicalAntialiasingPass = new SubpixelMorphologicalAntialiasingPass(mSettings);
	    m_SubpixelMorphologicalAntialiasingPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }


    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var dest = RenderTargetHandle.CameraTarget;
        m_SubpixelMorphologicalAntialiasingPass.Setup(renderer, dest);
        renderer.EnqueuePass(m_SubpixelMorphologicalAntialiasingPass);
    }

    #region Utils
    /// <summary>
    /// Helps debugging and fine tuning settings when working with <see cref="QualityPreset.Custom"/>.
    /// </summary>
    public enum DebugPass
    {
        /// <summary>
        /// Standard rendering, no debug pass is shown.
        /// </summary>
        Off,

        /// <summary>
        /// Shows the detected edges.
        /// </summary>
        Edges,

        /// <summary>
        /// Shows the computed blend weights.
        /// </summary>
        Weights
    }
    
    /// <summary>
    /// You have three edge detection methods to choose from: luma, color or depth.
    /// They represent different quality/performance and anti-aliasing/sharpness tradeoffs, so our recommendation is
    /// for you to choose the one that best suits your particular scenario.
    /// </summary>
    public enum EdgeDetectionMethod
    {
        /// <summary>
        /// Luma edge detection is usually more expensive than depth edge detection, but catches visible edges that
        /// depth edge detection can miss.
        /// </summary>
        Luma = 1,

        /// <summary>
        /// Color edge detection is usually the most expensive one but catches chroma-only edges.
        /// </summary>
        Color = 2,

        /// <summary>
        /// Depth edge detection is usually the fastest but it may miss some edges.
        /// </summary>
        Depth = 3
    }
    
    /// <summary>
    /// Render target mode. Keep it to <see cref="HDRMode.Auto"/> unless you know what you're doing.
    /// </summary>
    public enum HDRMode
    {
        Auto,
        On,
        Off
    }
    
    /// <summary>
    /// Holds a set of settings to use when <see cref="SMAA.UsePredication"/> is enabled.
    /// </summary>
    [System.Serializable]
    public class PredicationPreset
    {
        /// <summary>
        /// Threshold to be used in the additional predication buffer.
        /// </summary>
        [Min(0.0001f)]
        public float Threshold = 0.01f;

        /// <summary>
        /// How much to scale the global threshold used for luma or color edge detection when using predication.
        /// </summary>
        [Range(1f, 5f)]
        public float Scale = 2f;

        /// <summary>
        /// How much to locally decrease the threshold.
        /// </summary>
        [Range(0f, 1f)]
        public float Strength = 0.4f;
    }
    
    /// <summary>
    /// Holds a set of settings to use with SMAA passes.
    /// </summary>
	public class Preset
	{
		/// <summary>
		/// Enables/Disables diagonal processing.
		/// </summary>
		public bool DiagDetection = true;

		/// <summary>
		/// Enables/Disables corner detection. Leave this on to avoid blurry corners.
		/// </summary>
		public bool CornerDetection = true;

		/// <summary>
		/// Specifies the threshold or sensitivity to edges. Lowering this value you will be able to detect more edges
		/// at the expense of performance.
		/// <c>0.1</c> is a reasonable value, and allows to catch most visible edges. <c>0.05</c> is a rather overkill
		/// value, that allows to catch 'em all.
		/// </summary>
		[Range(0f, 0.5f)]
		public float Threshold = 0.1f;

		/// <summary>
		/// Specifies the threshold for depth edge detection. Lowering this value you will be able to detect more edges
		/// at the expense of performance. Only used with <see cref="SMAAEdgeDetectionMethod.Depth"/>.
		/// </summary>
		[Min(0.0001f)]
		public float DepthThreshold = 0.01f;

		/// <summary>
		/// Specifies the maximum steps performed in the horizontal/vertical pattern searches, at each side of the
		/// pixel. In number of pixels, it's actually the double. So the maximum line length perfectly handled by, for
		/// example <c>16</c> is <c>64</c> (by perfectly, we meant that longer lines won't look as good, but still
		/// antialiased).
		/// </summary>
		[Range(0, 112)]
		public int MaxSearchSteps = 16;

		/// <summary>
		/// Specifies the maximum steps performed in the diagonal pattern searches, at each side of the pixel. In this
		/// case we jump one pixel at time, instead of two.
		/// 
		/// On high-end machines it is cheap (between a 0.8x and 0.9x slower for <c>16</c> steps), but it can have a
		/// significant impact on older machines.
		/// </summary>
		[Range(0, 20)]
		public int MaxSearchStepsDiag = 8;

		/// <summary>
		/// Specifies how much sharp corners will be rounded.
		/// </summary>
		[Range(0, 100)]
		public int CornerRounding = 25;

		/// <summary>
		/// If there is an neighbor edge that has a local contrast factor times bigger contrast than current edge,
		/// current edge will be discarded.
		/// 
		/// This allows to eliminate spurious crossing edges, and is based on the fact that, if there is too much
		/// contrast in a direction, that will hide perceptually contrast in the other neighbors.
		/// 
		/// Currently unused in OpenGL.
		/// </summary>
		[Min(0f)]
		public float LocalContrastAdaptationFactor = 2f;
	}
	
    /// <summary>
    /// A bunch of quality presets. Use <see cref="QualityPreset.Custom"/> to fine tune every setting.
    /// </summary>
    public enum QualityPreset
    {
	    /// <summary>
	    /// 60% of the quality.
	    /// </summary>
	    Low = 0,

	    /// <summary>
	    /// 80% of the quality.
	    /// </summary>
	    Medium = 1,

	    /// <summary>
	    /// 90% of the quality.
	    /// </summary>
	    High = 2,

	    /// <summary>
	    /// 99% of the quality (generally overkill).
	    /// </summary>
	    Ultra = 3,

	    /// <summary>
	    /// Custom quality settings.
	    /// </summary>
	    /// <seealso cref="Preset"/>
	    /// <seealso cref="SMAA.CustomPreset"/>
	    Custom
    }
    #endregion
}
