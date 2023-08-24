using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.Universal.Internal;

public class TemporalAntiAliasingFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public AntialiasingQuality AAQuality = AntialiasingQuality.Low;//  抗锯齿质量
        [Range(0,1)]public float spread = 1;
        [Range(0,1)]public float feedback = 0;
    }

    static ScriptableRendererFeature s_Instance;
    CameraSettingPass m_cameraSettingPass;
    TemporalAntiAliasingPass m_TAAPass;
    Dictionary<Camera, TAAData> m_TAADatas;
    Matrix4x4 previewView;
    Matrix4x4 previewProj;
    
    const int k_SampleCount = 8;

    public static int sampleIndex { get; private set; }
    public Settings mSettings = new Settings();
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var camera = renderingData.cameraData.camera;
        TAAData TaaData;
        if (!m_TAADatas.TryGetValue(camera, out TaaData))
        {
            TaaData = new TAAData();
            m_TAADatas.Add(camera, TaaData);
        }
        
        UpdateTAAData(renderingData, TaaData, mSettings);
        m_cameraSettingPass.Setup(TaaData);
        renderer.EnqueuePass(m_cameraSettingPass);
        
        m_TAAPass.Setup(renderer, TaaData, mSettings);
        renderer.EnqueuePass(m_TAAPass);
    }
    
    public override void Create()
    {
        s_Instance = this;
        name = "TemporalAntiAliasing";
        m_cameraSettingPass = new CameraSettingPass();
        m_TAADatas = new Dictionary<Camera, TAAData>();
        m_TAAPass = new TemporalAntiAliasingPass(new Material(Shader.Find("TAA")));
    }
    /// <summary>
    /// Get
    /// </summary>
    /// <param name="index"></param>
    /// <param name="radix"></param>
    /// <returns></returns>
    public static float Get(int index, int radix)
    {
        float result = 0f;
        float fraction = 1f / (float)radix;

        while (index > 0)
        {
            result += (float)(index % radix) * fraction;

            index /= radix;
            fraction /= (float)radix;
        }

        return result;
    }
    
    /// <summary>
    /// GenerateRandomOffset
    /// </summary>
    /// <returns></returns>
    public static Vector2 GenerateRandomOffset()
    {
        // The variance between 0 and the actual halton sequence values reveals noticeable instability
        // in Unity's shadow maps, so we avoid index 0.
        var offset = new Vector2(
            Get((sampleIndex & 1023) + 1, 2) - 0.5f,
            Get((sampleIndex & 1023) + 1, 3) - 0.5f
        );

        if (++sampleIndex >= k_SampleCount)
            sampleIndex = 0;

        return offset;
    }
    
    /// <summary>
    /// GetJitteredOrthographicProjectionMatrix
    /// </summary>
    /// <param name="camera"></param>
    /// <param name="offset"></param>
    /// <returns></returns>
    public static Matrix4x4 GetJitteredOrthographicProjectionMatrix(Camera camera, Vector2 offset)
    {
        float vertical = camera.orthographicSize;
        float horizontal = vertical * camera.aspect;

        offset.x *= horizontal / (0.5f * camera.pixelWidth);
        offset.y *= vertical / (0.5f * camera.pixelHeight);

        float left = offset.x - horizontal;
        float right = offset.x + horizontal;
        float top = offset.y + vertical;
        float bottom = offset.y - vertical;

        return Matrix4x4.Ortho(left, right, bottom, top, camera.nearClipPlane, camera.farClipPlane);
    }
    
    /// <summary>
    /// GetJitteredPerspectiveProjectionMatrix
    /// </summary>
    /// <param name="camera"></param>
    /// <param name="offset"></param>
    /// <returns></returns>
    public static Matrix4x4 GetJitteredPerspectiveProjectionMatrix(Camera camera, Vector2 offset)
    {
        float near = camera.nearClipPlane;
        float far = camera.farClipPlane;

        float vertical = Mathf.Tan(0.5f * Mathf.Deg2Rad * camera.fieldOfView) * near;
        float horizontal = vertical * camera.aspect;

        offset.x *= horizontal / (0.5f * camera.pixelWidth);
        offset.y *= vertical / (0.5f * camera.pixelHeight);

        var matrix = camera.projectionMatrix;

        matrix[0, 2] += offset.x / horizontal;
        matrix[1, 2] += offset.y / vertical;

        return matrix;
    }
    
    /// <summary>
    /// Update TAA Data
    /// </summary>
    /// <param name="renderingData"></param>
    /// <param name="TaaData"></param>
    /// <param name="data"></param>
    void UpdateTAAData(RenderingData renderingData, TAAData TaaData, Settings settings)
    {
        Camera camera = renderingData.cameraData.camera;
        Vector2 additionalSample = GenerateRandomOffset()* settings.spread;
        TaaData.sampleOffset = additionalSample;
        TaaData.porjPreview = previewProj;
        TaaData.viewPreview = previewView;
        TaaData.projOverride = camera.orthographic
            ? GetJitteredOrthographicProjectionMatrix(camera, TaaData.sampleOffset)
            : GetJitteredPerspectiveProjectionMatrix(camera, TaaData.sampleOffset);
        TaaData.sampleOffset = new Vector2(TaaData.sampleOffset.x / camera.scaledPixelWidth, TaaData.sampleOffset.y / camera.scaledPixelHeight);
        previewView = camera.worldToCameraMatrix;
        previewProj = camera.projectionMatrix;
    }
    
}
