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
            #pragma vertex VS
            #pragma fragment PS
            ENDHLSL

        }

    }
}