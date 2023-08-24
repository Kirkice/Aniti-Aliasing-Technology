Shader "FxAA"
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
	        HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex VS
            #pragma fragment PS

            uniform float4 _FxAA_Params;
            #define AbsoluteLumaThreshold _FxAA_Params.x
            #define RelativeLumaThreshold _FxAA_Params.y
            #define SubpixelBlending _FxAA_Params.z

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
            uniform float4 _MainTex_TexelSize;
            CBUFFER_END

            struct Vertex_Input
            {
                float4 positionOS : POSITION;
                float4 TexC : TEXCOORD0;
            };

            struct Vertex_Output
            {
                float4 positionCS : SV_POSITION;
                float2 TexC : TEXCOORD0;
            };

            Vertex_Output VS(Vertex_Input vin)
            {
                Vertex_Output vout;
                vout.positionCS = TransformObjectToHClip(vin.positionOS.xyz);
                vout.TexC = vin.TexC;
                return vout;
            }

			float4 GetSource(float2 screenUV) {
				return SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, screenUV, 0);
			}
            
			float GetLuma (float2 uv, float uOffset = 0.0, float vOffset = 0.0) {
				uv += float2(uOffset, vOffset) * _MainTex_TexelSize.xy;
				#if defined(FXAA_ALPHA_CONTAINS_LUMA)
					return GetSource(uv).a;
				#else
					return GetSource(uv).g;
				#endif
			}

			struct LumaNeighborhood {
				float m, n, e, s, w, ne, se, sw, nw;
				float highest, lowest, range;
			};

			LumaNeighborhood GetLumaNeighborhood (float2 uv) {
				LumaNeighborhood luma;
				luma.m = GetLuma(uv);
				luma.n = GetLuma(uv, 0.0, 1.0);
				luma.e = GetLuma(uv, 1.0, 0.0);
				luma.s = GetLuma(uv, 0.0, -1.0);
				luma.w = GetLuma(uv, -1.0, 0.0);
				luma.ne = GetLuma(uv, 1.0, 1.0);
				luma.se = GetLuma(uv, 1.0, -1.0);
				luma.sw = GetLuma(uv, -1.0, -1.0);
				luma.nw = GetLuma(uv, -1.0, 1.0);

				luma.highest = max(max(max(max(luma.m, luma.n), luma.e), luma.s), luma.w);
				luma.lowest = min(min(min(min(luma.m, luma.n), luma.e), luma.s), luma.w);
				luma.range = luma.highest - luma.lowest;
				return luma;
			}

			bool IsHorizontalEdge (LumaNeighborhood luma) {
				float horizontal =
					2.0 * abs(luma.n + luma.s - 2.0 * luma.m) +
					abs(luma.ne + luma.se - 2.0 * luma.e) +
					abs(luma.nw + luma.sw - 2.0 * luma.w);
				float vertical =
					2.0 * abs(luma.e + luma.w - 2.0 * luma.m) +
					abs(luma.ne + luma.nw - 2.0 * luma.n) +
					abs(luma.se + luma.sw - 2.0 * luma.s);
				return horizontal >= vertical;
			}

			struct FXAAEdge {
				bool isHorizontal;
				float pixelStep;
				float lumaGradient, otherLuma;
			};

			FXAAEdge GetFXAAEdge (LumaNeighborhood luma) {
				FXAAEdge edge;
				edge.isHorizontal = IsHorizontalEdge(luma);
				float lumaP, lumaN;
				if (edge.isHorizontal) {
					edge.pixelStep = _MainTex_TexelSize.y;
					lumaP = luma.n;
					lumaN = luma.s;
				}
				else {
					edge.pixelStep = _MainTex_TexelSize.x;
					lumaP = luma.e;
					lumaN = luma.w;
				}
				float gradientP = abs(lumaP - luma.m);
				float gradientN = abs(lumaN - luma.m);

				if (gradientP < gradientN) {
					edge.pixelStep = -edge.pixelStep;
					edge.lumaGradient = gradientN;
					edge.otherLuma = lumaN;
				}
				else {
					edge.lumaGradient = gradientP;
					edge.otherLuma = lumaP;
				}
				
				return edge;
			}

			bool CanSkipFXAA (LumaNeighborhood luma) {
				return luma.range < max(AbsoluteLumaThreshold, RelativeLumaThreshold * luma.highest);
			}

			float GetSubpixelBlendFactor (LumaNeighborhood luma) {
				float filter = 2.0 * (luma.n + luma.e + luma.s + luma.w);
				filter += luma.ne + luma.nw + luma.se + luma.sw;
				filter *= 1.0 / 12.0;
				filter = abs(filter - luma.m);
				filter = saturate(filter / luma.range);
				filter = smoothstep(0, 1, filter);
				return filter * filter * SubpixelBlending;
			}

			#if defined(FXAA_QUALITY_LOW)
				#define EXTRA_EDGE_STEPS 3
				#define EDGE_STEP_SIZES 1.5, 2.0, 2.0
				#define LAST_EDGE_STEP_GUESS 8.0
			#elif defined(FXAA_QUALITY_MEDIUM)
				#define EXTRA_EDGE_STEPS 8
				#define EDGE_STEP_SIZES 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0
				#define LAST_EDGE_STEP_GUESS 8.0
			#else
				#define EXTRA_EDGE_STEPS 10
				#define EDGE_STEP_SIZES 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0
				#define LAST_EDGE_STEP_GUESS 8.0
			#endif

			static const float edgeStepSizes[EXTRA_EDGE_STEPS] = { EDGE_STEP_SIZES };

			float GetEdgeBlendFactor (LumaNeighborhood luma, FXAAEdge edge, float2 uv) {
				float2 edgeUV = uv;
				float2 uvStep = 0.0;
				if (edge.isHorizontal) {
					edgeUV.y += 0.5 * edge.pixelStep;
					uvStep.x = _MainTex_TexelSize.x;
				}
				else {
					edgeUV.x += 0.5 * edge.pixelStep;
					uvStep.y = _MainTex_TexelSize.y;
				}

				float edgeLuma = 0.5 * (luma.m + edge.otherLuma);
				float gradientThreshold = 0.25 * edge.lumaGradient;
						
				float2 uvP = edgeUV + uvStep;
				float lumaDeltaP = GetLuma(uvP) - edgeLuma;
				bool atEndP = abs(lumaDeltaP) >= gradientThreshold;

				UNITY_UNROLL
				for (int i = 0; i < EXTRA_EDGE_STEPS && !atEndP; i++) {
					uvP += uvStep * edgeStepSizes[i];
					lumaDeltaP = GetLuma(uvP) - edgeLuma;
					atEndP = abs(lumaDeltaP) >= gradientThreshold;
				}
				if (!atEndP) {
					uvP += uvStep * LAST_EDGE_STEP_GUESS;
				}

				float2 uvN = edgeUV - uvStep;
				float lumaDeltaN = GetLuma(uvN) - edgeLuma;
				bool atEndN = abs(lumaDeltaN) >= gradientThreshold;

				UNITY_UNROLL
				for (int i = 0; i < EXTRA_EDGE_STEPS && !atEndN; i++) {
					uvN -= uvStep * edgeStepSizes[i];
					lumaDeltaN = GetLuma(uvN) - edgeLuma;
					atEndN = abs(lumaDeltaN) >= gradientThreshold;
				}
				if (!atEndN) {
					uvN -= uvStep * LAST_EDGE_STEP_GUESS;
				}

				float distanceToEndP, distanceToEndN;
				if (edge.isHorizontal) {
					distanceToEndP = uvP.x - uv.x;
					distanceToEndN = uv.x - uvN.x;
				}
				else {
					distanceToEndP = uvP.y - uv.y;
					distanceToEndN = uv.y - uvN.y;
				}

				float distanceToNearestEnd;
				bool deltaSign;
				if (distanceToEndP <= distanceToEndN) {
					distanceToNearestEnd = distanceToEndP;
					deltaSign = lumaDeltaP >= 0;
				}
				else {
					distanceToNearestEnd = distanceToEndN;
					deltaSign = lumaDeltaN >= 0;
				}

				if (deltaSign == (luma.m - edgeLuma >= 0)) {
					return 0.0;
				}
				else {
					return 0.5 - distanceToNearestEnd / (distanceToEndP + distanceToEndN);
				}
			}

            float4 PS(Vertex_Output pin) : SV_Target
            {
				LumaNeighborhood luma = GetLumaNeighborhood(pin.TexC);
				
				if (CanSkipFXAA(luma)) {
					return GetSource(pin.TexC);
				}

				FXAAEdge edge = GetFXAAEdge(luma);
				float blendFactor = max(
					GetSubpixelBlendFactor(luma), GetEdgeBlendFactor (luma, edge, pin.TexC)
				);
				float2 blendUV = pin.TexC;
				if (edge.isHorizontal) {
					blendUV.y += blendFactor * edge.pixelStep;
				}
				else {
					blendUV.x += blendFactor * edge.pixelStep;
				}
				return GetSource(blendUV);
            }
            ENDHLSL
        }
    	
        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }
            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex VS
            #pragma fragment PS

            uniform float4 _FxAA_Params;
            #define AbsoluteLumaThreshold _FxAA_Params.x
            #define RelativeLumaThreshold _FxAA_Params.y
            #define ConsoleCharpness _FxAA_Params.z

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
            CBUFFER_END

            struct Vertex_Input
            {
                float4 positionOS : POSITION;
                float4 TexC : TEXCOORD0;
            };

            struct Vertex_Output
            {
                float4 positionCS : SV_POSITION;
                float2 TexC : TEXCOORD0;
            };

            Vertex_Output VS(Vertex_Input vin)
            {
                Vertex_Output vout;
                vout.positionCS = TransformObjectToHClip(vin.positionOS.xyz);
                vout.TexC = vin.TexC;
                return vout;
            }

            //究极抗锯齿
            #define FXAA_MAX_EAGE_SEARCH_SAMPLE_COUNT 12
            static half edgeSearchSteps[FXAA_MAX_EAGE_SEARCH_SAMPLE_COUNT] = {
                1, 1, 1, 1, 1,
                1.5, 2, 2, 2, 2,
                4, 8
            };

            struct FXAACrossData
            {
                half4 M;
                half4 N;
                half4 S;
                half4 W;
                half4 E;
            };

            struct FXAACornerData
            {
                half4 NW;
                half4 NE;
                half4 SW;
                half4 SE;
            };

            struct FXAAEdge
            {
                half2 dir;
                half2 normal;
                bool isHorz;
                half lumaEdge; //往normal方向偏移0.5个像素的亮度
                half4 oppRGBL;
            };

            inline float rgb2luma(half3 color)
            {
                return dot(color, half3(0.299, 0.587, 0.114));
            }

            inline half4 SampleLinear(Texture2D tex, float2 uv)
            {
                return tex.Sample(sampler_MainTex, uv);
            }

            inline half4 SampleRGBLumaLinear(Texture2D tex, float2 uv)
            {
                half3 color = SampleLinear(tex, uv).rgb;
                return half4(color, rgb2luma(color));
            }

            ///采集上下左右4个像素 + 中心像素
            inline FXAACrossData SampleCross(Texture2D tex, float2 uv, float4 offset)
            {
                FXAACrossData crossData;
                crossData.M = SampleRGBLumaLinear(tex, uv);
                crossData.S = SampleRGBLumaLinear(tex, uv + float2(0, -offset.y));
                crossData.N = SampleRGBLumaLinear(tex, uv + float2(0, offset.y));
                crossData.W = SampleRGBLumaLinear(tex, uv + float2(-offset.x, 0));
                crossData.E = SampleRGBLumaLinear(tex, uv + float2(offset.x, 0));
                return crossData;
            }

            inline half4 CalculateContrast(in FXAACrossData cross)
            {
                half lumaMin = min(min(min(cross.N.a, cross.S.a), min(cross.W.a, cross.E.a)), cross.M.a);
                half lumaMax = max(max(max(cross.N.a, cross.S.a), max(cross.W.a, cross.E.a)), cross.M.a);
                half lumaContrast = lumaMax - lumaMin;
                return half4(lumaContrast, lumaMin, lumaMax, 0);
            }

            //offset由(x,y,-x,-y)组成
            inline FXAACornerData SampleCorners(Texture2D tex, float2 uv, float4 offset)
            {
                FXAACornerData cornerData;
                half3 rgbNW = SampleLinear(tex, uv + offset.zy);
                half3 rgbSW = SampleLinear(tex, uv + offset.zw);
                half3 rgbNE = SampleLinear(tex, uv + offset.xy);
                half3 rgbSE = SampleLinear(tex, uv + offset.xw);

                cornerData.NW = half4(rgbNW, rgb2luma(rgbNW));
                cornerData.NE = half4(rgbNE, rgb2luma(rgbNE));
                cornerData.SW = half4(rgbSW, rgb2luma(rgbSW));
                cornerData.SE = half4(rgbSE, rgb2luma(rgbSE));
                return cornerData;
            }

            inline FXAAEdge GetEdge(in FXAACrossData cross, in FXAACornerData corner)
            {
                FXAAEdge edge;

                half lumaM = cross.M.a;
                half lumaN = cross.N.a;
                half lumaS = cross.S.a;
                half lumaW = cross.W.a;
                half lumaE = cross.E.a;

                half lumaGradS = lumaS - lumaM;
                half lumaGradN = lumaN - lumaM;
                half lumaGradW = lumaW - lumaM;
                half lumaGradE = lumaE - lumaM;

                half lumaGradH = abs(lumaGradW + lumaGradE);
                half lumaGradV = abs(lumaGradS + lumaGradN);

                half lumaNW = corner.NW.a;
                half lumaNE = corner.NE.a;
                half lumaSW = corner.SW.a;
                half lumaSE = corner.SE.a;

                lumaGradH = abs(lumaNW + lumaNE - 2 * lumaN)
                    + 2 * lumaGradH
                    + abs(lumaSW + lumaSE - 2 * lumaS);

                lumaGradV = abs(lumaNW + lumaSW - 2 * lumaW)
                    + 2 * lumaGradV
                    + abs(lumaNE + lumaSE - 2 * lumaE);

                bool isHorz = lumaGradV >= lumaGradH;
                edge.isHorz = isHorz;
                if (isHorz)
                {
                    half s = sign(abs(lumaGradN) - abs(lumaGradS));
                    edge.dir = half2(1, 0);
                    edge.normal = half2(0, s);
                    edge.lumaEdge = s > 0 ? (lumaN + lumaM) * 0.5 : (lumaS + lumaM) * 0.5;
                    edge.oppRGBL = s > 0 ? cross.N : cross.S;
                }
                else
                {
                    half s = sign(abs(lumaGradE) - abs(lumaGradW));
                    edge.dir = half2(0, 1);
                    edge.normal = half2(s, 0);
                    edge.lumaEdge = s > 0 ? (lumaE + lumaM) * 0.5 : (lumaW + lumaM) * 0.5;
                    edge.oppRGBL = s > 0 ? cross.E : cross.W;
                }
                return edge;
            }

            inline half GetLumaGradient(FXAAEdge edge, FXAACrossData crossData)
            {
                half luma1, luma2;
                half lumaM = crossData.M.a;
                if (edge.isHorz)
                {
                    luma1 = crossData.S.a;
                    luma2 = crossData.N.a;
                }
                else
                {
                    luma1 = crossData.W.a;
                    luma2 = crossData.E.a;
                }
                return max(abs(lumaM - luma1), abs(lumaM - luma2));
            }

            inline float GetEdgeBlend(Texture2D tex, float2 uv, FXAAEdge edge, FXAACrossData crossData)
            {
                float2 invScreenSize = (_ScreenParams.zw - 1);

                half lumaM = crossData.M.a;
                half lumaGrad = GetLumaGradient(edge, crossData);
                half lumaGradScaled = lumaGrad * 0.25;
                uv += edge.normal * 0.5 * invScreenSize;

                half2 dir = edge.dir;

                float lumaStart = edge.lumaEdge;

                half4 rgblP, rgblN;

                float2 posP = float2(0, 0);
                float2 posN = float2(0, 0);
                bool endP = false;
                bool endN = false;

                for (uint i = 0; i < FXAA_MAX_EAGE_SEARCH_SAMPLE_COUNT; i ++)
                {
                    half step = edgeSearchSteps[i];
                    if (!endP)
                    {
                        posP += step * dir;
                        rgblP = SampleRGBLumaLinear(tex, uv + posP * invScreenSize);
                        endP = abs(rgblP.a - lumaStart) > lumaGradScaled;
                    }
                    if (!endN)
                    {
                        posN -= step * dir;
                        rgblN = SampleRGBLumaLinear(tex, uv + posN * invScreenSize);
                        endN = abs(rgblN.a - lumaStart) > lumaGradScaled;
                    }
                    if (endP && endN)
                    {
                        break;
                    }
                }
                posP = abs(posP);
                posN = abs(posN);
                float dstP = max(posP.x, posP.y);
                float dstN = max(posN.x, posN.y);
                float dst, lumaEnd;
                if (dstP > dstN)
                {
                    dst = dstN;
                    lumaEnd = rgblN.a;
                }
                else
                {
                    dst = dstP;
                    lumaEnd = rgblP.a;
                }
                if ((lumaM - lumaStart) * (lumaEnd - lumaStart) > 0)
                {
                    return 0;
                }
                //blend的范围为0~0.5
                return 0.5 - dst / (dstP + dstN);
            }

            float4 PS(Vertex_Output pin) : SV_Target
            {
                float2 invTextureSize = (_ScreenParams.zw - 1);
                float4 offset = float4(1, 1, -1, -1) * invTextureSize.xyxy * 0.5;
                FXAACornerData corner = SampleCorners(_MainTex, pin.TexC, offset);
                corner.NE.a += 1.0 / 384.0;
                half4 rgblM = SampleRGBLumaLinear(_MainTex, pin.TexC);

                half maxLuma = max(max(corner.NW.a, corner.NE.a), max(corner.SW.a, corner.SE.a));
                half minLuma = min(min(corner.NW.a, corner.NE.a), min(corner.SW.a, corner.SE.a));
                half lumaContrast = max(rgblM.a, maxLuma) - min(rgblM.a, minLuma);
                half edgeContrastThreshold = max(AbsoluteLumaThreshold, maxLuma * RelativeLumaThreshold);

                if (lumaContrast > edgeContrastThreshold)
                {
                    half2 dir;
                    // dir.x = (corner.SW.a + corner.SE.a) - (corner.NW.a + corner.NE.a);
                    // dir.y = (corner.NW.a + corner.SW.a) - (corner.NE.a + corner.SE.a);
                    half sWMinNE = corner.SW.a - corner.NE.a;
                    half sEMinNW = corner.SE.a - corner.NW.a;
                    dir.x = sWMinNE + sEMinNW;
                    dir.y = sWMinNE - sEMinNW;

                    dir = normalize(dir);

                    half4 rgblP1 = SampleRGBLumaLinear(_MainTex, pin.TexC + dir * invTextureSize * 0.5);
                    half4 rgblN1 = SampleRGBLumaLinear(_MainTex, pin.TexC - dir * invTextureSize * 0.5);

                    float dirAbsMinTimesC = min(abs(dir.x), abs(dir.y)) * ConsoleCharpness;
                    float2 dir2 = clamp(dir / dirAbsMinTimesC, -2, 2);

                    half4 rgblP2 = SampleRGBLumaLinear(_MainTex, pin.TexC + dir2 * invTextureSize * 2);
                    half4 rgblN2 = SampleRGBLumaLinear(_MainTex, pin.TexC - dir2 * invTextureSize * 2);

                    half4 rgblA = rgblP1 + rgblN1;
                    half4 rgblB = (rgblP2 + rgblN2) * 0.25 + rgblA * 0.25;

                    bool twoTap = rgblB.a < minLuma || rgblB.a > maxLuma;

                    if (twoTap)
                    {
                        rgblB.rgb = rgblA.rgb * 0.5;
                    }
                    return half4(rgblB.rgb, 1);
                }
                else
                    return rgblM;
            }
            ENDHLSL
        }
    }
}