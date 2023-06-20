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

        HLSLPROGRAM
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        uniform float4 _MLAA_PARAMS;
        #define threshold _MLAA_PARAMS.x
        #define RelativeLumaThreshold _MLAA_PARAMS.y
        #define ConsoleCharpness _MLAA_PARAMS.z

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

                    // AMD Morphological Anti-Aliasing (MLAA) Sample
            //
            // https://github.com/GPUOpen-LibrariesAndSDKs/MLAA11
            //
            // Copyright (c) 2016 Advanced Micro Devices, Inc. All rights reserved.
            //
            // Permission is hereby granted, free of charge, to any person obtaining a copy
            // of this software and associated documentation files (the "Software"), to deal
            // in the Software without restriction, including without limitation the rights
            // to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            // copies of the Software, and to permit persons to whom the Software is
            // furnished to do so, subject to the following conditions:
            //
            // The above copyright notice and this permission notice shall be included in
            // all copies or substantial portions of the Software.
            //
            // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
            // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            // OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
            // THE SOFTWARE.
            //

            //-----------------------------------------------------------------------------------------
            // File: MLAA11.hlsl
            //
            // Set of shaders used to apply Morphological Anti-Aliasing (MLAA) to a scene
            // as a post-process operation.
            //
            // GLSL-Port 2023 by Denis Reischl
            //-----------------------------------------------------------------------------------------

            //-----------------------------------------------------------------------------------------
            // Defines
            //-----------------------------------------------------------------------------------------
            #ifndef MAX_EDGE_COUNT_BITS
            #define MAX_EDGE_COUNT_BITS			4			// Default edge count bits is 4
            #endif

            #ifndef SHOW_EDGES
            #define SHOW_EDGES					0			// Disabled by default      
            #endif

            #ifndef USE_STENCIL
            #define USE_STENCIL					0			// Disabled by default      
            #endif

            //#define USE_GATHER                            // Disabled by default

            //-----------------------------------------------------------------------------------------
            // Static Constants
            //-----------------------------------------------------------------------------------------
            // Set the number of bits to use when storing the horizontal and vertical counts
            // This number should be half the number of bits in the color channels used
            // E.g. with a RT format of DXGI_R8G8_int this number should be 8/2 = 4
            // Longer edges can be detected by increasing this number; however this requires a 
            // larger bit depth format, and also makes the edge length detection function slower
            const uint kNumCountBits = uint(MAX_EDGE_COUNT_BITS);

            // The maximum edge length that can be detected
            const uint kMaxEdgeLength = ((1u << (kNumCountBits - 1u)) - 1u);

            // Various constants used by the shaders below
            const uint kUpperMask = (1u << 0u);
            const uint kUpperMask_BitPosition = 0u;
            const uint kRightMask = (1u << 1u);
            const uint kRightMask_BitPosition = 1u;
            const uint kStopBit = (1u << (kNumCountBits - 1u));
            const uint kStopBit_BitPosition = (kNumCountBits - 1u);
            const uint kNegCountShift = (kNumCountBits);
            const uint kPosCountShift = (00u);
            const uint kCountShiftMask = ((1u << kNumCountBits) - 1u);

            const float3 kZero = float3(0, 0, 0);
            const float3 kUp = float3(0, -1, 0);
            const float3 kDown = float3(0, 1, 0);
            const float3 kRight = float3(1, 0, 0);
            const float3 kLeft = float3(-1, 0, 0);

            // This constant defines the luminance intensity difference to check for when testing any 
            // two pixels for an edge.
            const float fInvEdgeDetectionTreshold = 1.f / 32.f;

            //-----------------------------------------------------------------------------------------
            // Utility functions
            //-----------------------------------------------------------------------------------------
            //--------------------------------------------------------------------------------------
            // Returns true if the colors are different
            //--------------------------------------------------------------------------------------
            bool CompareColors(float a, float b)
            {
                return (abs(a - b) > fInvEdgeDetectionTreshold);
            }

            float2 CompareColors2(float2 a, float2 b)
            {
                return float2(abs(a.x - b.x) > fInvEdgeDetectionTreshold, abs(a.y - b.y) > fInvEdgeDetectionTreshold);
            }

            //--------------------------------------------------------------------------------------
            //--------------------------------------------------------------------------------------
            uint RemoveStopBit(uint a)
            {
                return a & (kStopBit - 1u);
            }

            //--------------------------------------------------------------------------------------
            //--------------------------------------------------------------------------------------
            uint DecodeCountNoStopBit(uint count, uint shift)
            {
                return RemoveStopBit((count >> shift) & kCountShiftMask);
            }

            //--------------------------------------------------------------------------------------
            //--------------------------------------------------------------------------------------
            uint DecodeCount(uint count, uint shift)
            {
                return (count >> shift) & kCountShiftMask;
            }

            //--------------------------------------------------------------------------------------
            //--------------------------------------------------------------------------------------
            uint EncodeCount(uint negCount, uint posCount)
            {
                return ((negCount & kCountShiftMask) << kNegCountShift) | (posCount & kCountShiftMask);
            }

            //-----------------------------------------------------------------------------
            // uvec4 <-> FLOAT4 ( B8G8R8A8_UNORM )
            // modified code from "d3dx_dxgiformatconvert.inl"
            //-----------------------------------------------------------------------------
            uint D3DX_FLOAT_to_UINT(float _V, float _Scale) { return uint(floor(_V * _Scale + 0.5f)); }

            float4 UINT4_to_FLOAT4_D3DX_B8G8R8A8_UNORM(float4 Input)
            {
                float4 Output;
                Output.z = float(Input.x & 0x000000ffu) / 255.f;
                Output.y = float(Input.y & 0x000000ffu) / 255.f;
                Output.x = float(Input.z & 0x000000ffu) / 255.f;
                Output.w = float(Input.w & 0x000000ffu) / 255.f;
                return Output;
            }

            float4 D3DX_FLOAT4_to_UINT4_B8G8R8A8_UNORM(float4 Input)
            {
                float4 Output;
                Output = float4(D3DX_FLOAT_to_UINT(clamp(Input.z, 0.f, 1.f), 255.f),
                                D3DX_FLOAT_to_UINT(clamp(Input.y, 0.f, 1.f), 255.f),
                                D3DX_FLOAT_to_UINT(clamp(Input.x, 0.f, 1.f), 255.f),
                                D3DX_FLOAT_to_UINT(clamp(Input.w, 0.f, 1.f), 255.f));
                return Output;
            }


            //-----------------------------------------------------------------------------	
            //	Main function used in third and final phase of the algorithm
            //	This code reads previous inputs and perform anti-aliasing of edges by 
            //  blending colors as required.
            //-----------------------------------------------------------------------------
            void BlendColor(TEXTURE2D(tex),
                            SAMPLER(sampler),
                            uint count,
                            float2 pos,
                            float2 dir,
                            float2 ortho,
                            bool _inverse,
                            inout float4 color)
            {
                // Only process pixel edge if it contains a stop bit
                if (IsBitSet(count, kStopBit_BitPosition + kPosCountShift) || IsBitSet(
                    count, kStopBit_BitPosition + kNegCountShift))
                {
                    // Retrieve edge length
                    uint negCount = DecodeCountNoStopBit(count, kNegCountShift);
                    uint posCount = DecodeCountNoStopBit(count, kPosCountShift);

                    // Fetch color adjacent to the edge
                    float4 adjacentcolor = SAMPLE_TEXTURE2D(tex, sampler, pos + dir, 0);

                    if ((negCount + posCount) == 0u)
                    {
                        float weight = 1.0 / 8.0; // Arbitrary			
                        // Cheap approximation of gamma to linear and then back again
                        color.xyz = sqrt(lerp(color.xyz * color.xyz, adjacentcolor.xyz * adjacentcolor.xyz, weight));
                        return;
                    }
                    else
                    {
                        // If no sign bit is found on either edge then artificially increase the edge length so that
                        // we don't start anti-aliasing pixels for which we don't have valid data.
                        if (!(IsBitSet(count, (kStopBit_BitPosition + kPosCountShift)))) posCount = kMaxEdgeLength + 1u;
                        if (!(IsBitSet(count, (kStopBit_BitPosition + kNegCountShift)))) negCount = kMaxEdgeLength + 1u;

                        // Calculate some variables
                        float _length = float(negCount + posCount) + 1.f;
                        float midPoint = _length / 2.f;
                        float _distance = float(negCount);

                        const uint upperU = 0x00u;
                        const uint risingZ = 0x01u;
                        const uint fallingZ = 0x02u;
                        const uint lowerU = 0x03u;

                        ///////////////////////////////////////////////////////////////////////////////////////
                        // Determining what pixels to blend
                        // 4 possible values for shape - x indicates a blended pixel:
                        //
                        // 0: |xxxxxx| -> (h0 > 0) && (h1 > 0) : upperU     - blend along the entire inverse edge
                        //     ------
                        //
                        //
                        // 1:     xxx| -> (h0 < 0) && (h1 > 0) : risingZ    - blend first half on inverse, 
                        //     ------                                         blend second half on non-inverse
                        //    |xxx                                            
                        //
                        // 2: |xxx     -> (h0 > 0) && (h1 < 0) : fallingZ   - blend first half on non-inverse, 
                        //     ------                                         blend second half on inverse
                        //        xxx|                                        
                        //
                        // 3:          -> (h0 < 0) && (h1 < 0) : lowerU     - blend along the entire non-inverse edge
                        //     ------
                        //    |xxxxxx|
                        ///////////////////////////////////////////////////////////////////////////////////////

                        uint shape = 0x00u;
                        if (CompareColors((SAMPLE_TEXTURE2D(tex,sampler, pos - (ortho * float2(int(negCount).xx)), 0).a),
                                          (SAMPLE_TEXTURE2D(tex,sampler, pos - (ortho * (float2((int(negCount) + 1).xx))), 0).a)))
                        {
                            shape |= risingZ;
                        }

                        if (CompareColors((SAMPLE_TEXTURE2D(tex,sampler, pos + (ortho * float2(int(posCount).xx)), 0).a),
                                          (SAMPLE_TEXTURE2D(tex,sampler, pos + (ortho * (float2((int(posCount) + 1).xx))), 0).a)))
                        {
                            shape |= fallingZ;
                        }

                        // Parameter "_inverse" is hard-coded on call so will not generate a dynamic branch condition
                        if ((_inverse && (((shape == fallingZ) && (float(negCount) <= midPoint)) ||
                                ((shape == risingZ) && (float(negCount) >= midPoint)) ||
                                ((shape == upperU))))
                            || (!_inverse && (((shape == fallingZ) && (float(negCount) >= midPoint)) ||
                                ((shape == risingZ) && (float(negCount) <= midPoint)) ||
                                ((shape == lowerU)))))
                        {
                            float h0 = abs((1.0 / _length) * (_length - _distance) - 0.5);
                            float h1 = abs((1.0 / _length) * (_length - _distance - 1.0) - 0.5);
                            float area = 0.5f * (h0 + h1);
                            // Cheap approximation of gamma to linear and then back again
                            color.xyz = sqrt(lerp(color.xyz * color.xyz, adjacentcolor.xyz * adjacentcolor.xyz, area));
                        }
                    }
                }
            }

            //-----------------------------------------------------------------------------
            //	MLAA pixel shader for color blending.
            //	Pixel shader used in third and final phase of the algorithm
            //-----------------------------------------------------------------------------
            float4 MLAA_BlendColor_PS(float2 uv, float2 Offset, bool bShowEdgesOnly)
            {
                if (bShowEdgesOnly)
                {
                    float4 rVal = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, uv + Offset, 0);

                    uint hcount, vcount;
                    float2 _count = D3DX_FLOAT4_to_UINT4_B8G8R8A8_UNORM(
                        SAMPLE_TEXTURE2D_LOD(_EdgeTex, sampler_EdgeTex, uv + Offset, 0)).xy;
                    hcount = _count.x;
                    vcount = _count.y;

                    if ((hcount != 0u) || (vcount != 0u))
                    {
                        if ((IsBitSet(hcount, kStopBit_BitPosition + kPosCountShift) || IsBitSet(
                                hcount, kStopBit_BitPosition + kNegCountShift)) ||
                            (IsBitSet(vcount, kStopBit_BitPosition + kPosCountShift) || IsBitSet(
                                vcount, kStopBit_BitPosition + kNegCountShift)))
                        {
                            uint Count = 0u;
                            Count += DecodeCountNoStopBit(hcount, kNegCountShift);
                            Count += DecodeCountNoStopBit(hcount, kPosCountShift);
                            Count += DecodeCountNoStopBit(vcount, kNegCountShift);
                            Count += DecodeCountNoStopBit(vcount, kPosCountShift);
                            if (Count != 0u)
                                rVal = float4(1, 0, 0, 1);
                        }
                    }
                    return rVal;
                }
                else
                {
                    uint hcount, vcount;
                    uint hcountup, vcountright;

                    float2 _count = D3DX_FLOAT4_to_UINT4_B8G8R8A8_UNORM(
                        SAMPLE_TEXTURE2D_LOD(_EdgeTex, sampler_EdgeTex, uv + Offset, 0)).xy;
                    hcount = _count.x;
                    vcount = _count.y;
                    hcountup = D3DX_FLOAT4_to_UINT4_B8G8R8A8_UNORM(
                        SAMPLE_TEXTURE2D_LOD(_EdgeTex, sampler_EdgeTex, uv + Offset - kUp.xy, 0)).x;
                    vcountright = D3DX_FLOAT4_to_UINT4_B8G8R8A8_UNORM(
                            SAMPLE_TEXTURE2D_LOD(_EdgeTex, sampler_EdgeTex, uv + Offset - kRight.xy, 0)).
                        y;

                    // Retrieve pixel from original image
                    float4 rVal = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, uv + Offset, 0);
                    // Blend pixel colors as required for anti-aliasing edges
                    if (hcount != 0u) BlendColor(_MainTex,sampler_MainTex, hcount, Offset, kUp.xy, kRight.xy, false, rVal); // H down-up
                    if (hcountup != 0u) BlendColor(_MainTex,sampler_MainTex, hcountup, Offset - kUp.xy, -kUp.xy, kRight.xy, true, rVal);
                    // H up-down    				    
                    if (vcount != 0u) BlendColor(_MainTex,sampler_MainTex, vcount, Offset, kRight.xy, kUp.xy, false, rVal);
                    // V left-right				
                    if (vcountright != 0u)
                        BlendColor(_MainTex,sampler_MainTex, vcountright, Offset - kRight.xy, -kRight.xy, kUp.xy,
                                   true, rVal); // V right-left    			

                    return rVal;
                }
            }
        
        float4 PS(Vertex_Output pin) : SV_Target
        {
            float D = SampleRGBLumaLinear(_MainTex, pin.TexC);
            float Dleft = SampleRGBLumaLinear(_MainTex, pin.TexC - int2(1, 0));
            float Dtop = SampleRGBLumaLinear(_MainTex, pin.TexC - int2(0, 1));
            float Dright = SampleRGBLumaLinear(_MainTex, pin.TexC + int2(1, 0));
            float Dbottom = SampleRGBLumaLinear(_MainTex, pin.TexC + int2(0, 1));
            
            float4 delta = abs(D.xxxx - float4(Dleft, Dtop, Dright, Dbottom));
            float4 edges = step(threshold.xxxx, delta);
            
            if (dot(edges, 1.0) == 0.0) 
                discard;

            return edges;
        }
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }
            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex VS
            #pragma fragment PS
            ENDHLSL
            
        }
    }
}