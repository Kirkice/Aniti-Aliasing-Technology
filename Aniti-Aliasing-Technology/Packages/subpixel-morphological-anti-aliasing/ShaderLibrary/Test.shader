Shader "Hidden/Test"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        //  dilate 
        Pass
        {
            Cull Off ZWrite Off ZTest Always

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            half4 TextureSize;
            
            #define MaxSteps 256
            
            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

           half3 dilate(half2 uv)
           {
                half2 texelsize = 1 / TextureSize.xy;
                float mindist = 100;
                half2 offsets[8] = {
                    half2(-1, 0), half2(1, 0), half2(0, 1), half2(0, -1), half2(-1, 1), half2(1, 1),
                    half2(1, -1), half2(-1, -1)
                };
                half3 sample = tex2Dlod(_MainTex,float4(uv,0,1));
                half3 curminsample = sample;

                if (sample.x == 0 && sample.y == 0 && sample.z == 0)
                {
                    int i = 0;
                    while (i < MaxSteps)
                    {
                        i++;
                        int j = 0;
                        while (j < 8)
                        {
                            half2 curUV = uv + offsets[j] * texelsize * i;
                            half3 offsetsample = tex2Dlod(_MainTex,float4(curUV,0,1));

                            if (offsetsample.x != 0 || offsetsample.y != 0 || offsetsample.z != 0)
                            {
                                float curdist = length(uv - curUV);

                                if (curdist < mindist)
                                {
                                    half2 projectUV = curUV + offsets[j] * texelsize * i * 0.25;
                                    half3 direction = tex2Dlod(_MainTex,float4(projectUV,0,1));;
                                    mindist = curdist;
                                    curminsample = max(offsetsample, direction);
                                }
                            }
                            j++;
                        }
                    }
                }

                return curminsample;
            }
            
            fixed4 frag(v2f i) : SV_Target
            {
                return fixed4(dilate(i.uv), 1);
            }
            ENDCG
        }
    }
}