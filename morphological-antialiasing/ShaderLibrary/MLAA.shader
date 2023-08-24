Shader "MLAA"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #include "MLAA.hlsl"
            #pragma vertex ScreenQuadVS
            #pragma fragment MLAA_SeperatingLines_PS
            ENDHLSL
        }

        Pass
        {
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #include "MLAA.hlsl"
            #pragma vertex ScreenQuadVS
            #pragma fragment MLAA_ComputeLineLength_PS
            ENDHLSL
        }
        
        Pass
        {
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #include "MLAA.hlsl"
            #pragma vertex ScreenQuadVS
            #pragma fragment MLAA_BlendColor_PS
            ENDHLSL
        }
    }
}