
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    uniform float4 _MLAA_PARAMS;
    #define threshold _MLAA_PARAMS.x
    #define RelativeLumaThreshold _MLAA_PARAMS.y
    #define ConsoleCharpness _MLAA_PARAMS.z

    TEXTURE2D(_MainTex);
    SAMPLER(sampler_MainTex);

	TEXTURE2D(_EdgeMaskTex);
	SAMPLER(sampler_EdgeMaskTex);

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

#define UINT						uint
#define UINT2						uint2
#define UINT4						uint4
#define FLATTEN						[flatten]
#define BRANCH						[branch]
#define UNROLL						[unroll]

//-----------------------------------------------------------------------------------------
// Static Constants
//-----------------------------------------------------------------------------------------
// Set the number of bits to use when storing the horizontal and vertical counts
// This number should be half the number of bits in the color channels used
// E.g. with a RT format of DXGI_R8G8_int this number should be 8/2 = 4
// Longer edges can be detected by increasing this number; however this requires a 
// larger bit depth format, and also makes the edge length detection function slower
static const UINT kNumCountBits				= MAX_EDGE_COUNT_BITS;

// The maximum edge length that can be detected
static const UINT kMaxEdgeLength			= ( (1<<(kNumCountBits-1)) - 1 );

// Various constants used by the shaders below
static const UINT kUpperMask				= (1<<0);
static const UINT kUpperMask_BitPosition	= 0;
static const UINT kRightMask				= (1<<1);
static const UINT kRightMask_BitPosition	= 1;
static const UINT kStopBit					= (1<<(kNumCountBits-1));
static const UINT kStopBit_BitPosition		= (kNumCountBits-1);
static const UINT kNegCountShift			= (kNumCountBits);
static const UINT kPosCountShift			= (00);
static const UINT kCountShiftMask			= ((1<<kNumCountBits)-1);

static const int3 kZero						= int3( 0,  0, 0);
static const int3 kUp						= int3( 0, -1, 0);
static const int3 kDown						= int3( 0,  1, 0);
static const int3 kRight					= int3( 1,  0, 0);
static const int3 kLeft						= int3(-1,  0, 0);

//-----------------------------------------------------------------------------------------
// Utility functions
//-----------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
// Returns true if the colors are different
//--------------------------------------------------------------------------------------
// This constant defines the luminance intensity difference to check for when testing any 
// two pixels for an edge.
const float fInvEdgeDetectionTreshold = 1.f / 32.f;

bool CompareColors(float a, float b)
{
    return ( abs(a - b)  > fInvEdgeDetectionTreshold );
}
bool2 CompareColors2(float2 a, float2 b)
{
	return bool2(abs(a.x - b.x) > fInvEdgeDetectionTreshold, abs(a.y - b.y) > fInvEdgeDetectionTreshold);
}
	
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT RemoveStopBit(UINT a)
{
	return a & (kStopBit-1);
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT DecodeCountNoStopBit(UINT count, UINT shift)
{
	return RemoveStopBit((count >> shift) & kCountShiftMask);
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT DecodeCount(UINT count, UINT shift)
{
	return (count >> shift) & kCountShiftMask;
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT EncodeCount(UINT negCount, UINT posCount)
{
	return ((negCount & kCountShiftMask) << kNegCountShift) | (posCount & kCountShiftMask);
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
uint EncodeMaskColor(UINT mask)
{
	return uint(mask);		
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT DecodeMaskColor(uint mask)
{
	return UINT(mask);		
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT4 DecodeMaskColor4(uint4 mask)
{
	return UINT4(mask);		
}	
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
uint EncodeCountColor(UINT count)
{
	return uint(count);
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT DecodeCountColor(uint count)
{
	return UINT(count);
}
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
UINT2 DecodeCountColor2(uint2 count)
{
	return UINT2(count);
}

//-----------------------------------------------------------------------------
// uvec4 <-> FLOAT4 ( B8G8R8A8_UNORM )
// modified code from "d3dx_dxgiformatconvert.inl"
//-----------------------------------------------------------------------------
uint D3DX_FLOAT_to_UINT(float _V, float _Scale) { return uint(floor(_V * _Scale + 0.5f)); }

float4 UINT4_to_FLOAT4_D3DX_B8G8R8A8_UNORM(uint4 Input)
{
	float4 Output;
	Output.z = float(Input.x & 0x000000ffu) / 255;
	Output.y = float(Input.y & 0x000000ffu) / 255;
	Output.x = float(Input.z & 0x000000ffu) / 255;
	Output.w = float(Input.w & 0x000000ffu) / 255;
	return Output;
}

uint4 D3DX_FLOAT4_to_UINT4_B8G8R8A8_UNORM(float4 Input)
{
	uint4 Output;
	Output = uint4( D3DX_FLOAT_to_UINT(clamp(Input.z, 0.f, 1.f), 255.f),
					D3DX_FLOAT_to_UINT(clamp(Input.y, 0.f, 1.f), 255.f),
					D3DX_FLOAT_to_UINT(clamp(Input.x, 0.f, 1.f), 255.f),
					D3DX_FLOAT_to_UINT(clamp(Input.w, 0.f, 1.f), 255.f));
	return Output;
}

//----------------------------------------------------------------------------
//	MLAA pixel shader for edge detection.
//	Pixel shader used in the first phase of MLAA.
//	This pixel shader is used to detect vertical and horizontal edges.
//-----------------------------------------------------------------------------
uint MLAA_SeperatingLines(float2 uv)
{
	int2 TextureSize = _ScreenParams.xy - 1;			
	int2 Offset = uv * _ScreenParams.xy;	
		
    float2 center;
	float2 upright;
	
    center.xy = _MainTex.Load(int3(clamp(Offset,int2(0, 0), TextureSize), 0)).a;	
    upright.y = _MainTex.Load(int3(clamp(Offset+kUp.xy,    int2(0, 0), TextureSize), 0)).a;
    upright.x = _MainTex.Load(int3(clamp(Offset+kRight.xy, int2(0, 0), TextureSize), 0)).a;			

	UINT rVal = 0;		
	
	bool2 result = CompareColors2(center, upright);
	
	
	// Check for seperating lines
	if ( result.y ) 
		rVal |= kUpperMask;
	if ( result.x )
		rVal |= kRightMask;
	
	return rVal;
}	


//-----------------------------------------------------------------------------
//	Pixel shader for the second phase of the algorithm.
//	This pixel shader calculates the length of edges.
//-----------------------------------------------------------------------------
uint2 MLAA_ComputeLineLength( float2 uv) 
{
	int2 TextureSize = _ScreenParams.xy - 1;
	int2 Offset = uv * _ScreenParams.xy;	
	
	// Retrieve edge mask for current pixel	
	UINT pixel = DecodeMaskColor(_EdgeMaskTex.Load(int3(Offset, 0)).r);	
    UINT4 EdgeCount = UINT4(0, 0, 0, 0); // x = Horizontal Count Negative, y = Horizontal Count Positive, z = Vertical Count Negative, w = Vertical Count Positive				    
    
    // We use a single branch for vertical and horizontal edge testing
	// Doing this is faster than two different branches (one for vertical, one for horizontal)
	// In most case both V and H edges are spatially coherent (apart from purely horizontal or 
	// vertical edges but those don't happen often compared to other cases).				
	BRANCH	
	if ( (pixel & (kUpperMask | kRightMask)) )	
	{
		static UINT4 EdgeDirMask = UINT4(kUpperMask, kUpperMask, kRightMask, kRightMask);		
		UINT4 EdgeFound = (pixel & EdgeDirMask) ? 0xFFFFFFFF : 0;								
		UINT4 StopBit = EdgeFound ? kStopBit : 0;  // Nullify the stopbit if we're not supposed to look at this edge							
		
		UNROLL
		for (int i=1; i<=int(kMaxEdgeLength); i++)
		{
			UINT4 uEdgeMask;			
			
			uEdgeMask.x = _EdgeMaskTex.Load(int3(clamp(Offset + int2(-i,  0), int2(0, 0), TextureSize), 0)).r;
			uEdgeMask.y = _EdgeMaskTex.Load(int3(clamp(Offset + int2( i,  0), int2(0, 0), TextureSize), 0)).r;
			uEdgeMask.z = _EdgeMaskTex.Load(int3(clamp(Offset + int2( 0,  i), int2(0, 0), TextureSize), 0)).r;				
			uEdgeMask.w = _EdgeMaskTex.Load(int3(clamp(Offset + int2( 0, -i), int2(0, 0), TextureSize), 0)).r;		
						
			EdgeFound = EdgeFound & (uEdgeMask & EdgeDirMask);
			EdgeCount = EdgeFound ? (EdgeCount + 1) : (EdgeCount | StopBit);				
		}						
	}    
    return uint2(EncodeCountColor(EncodeCount(EdgeCount.x, EdgeCount.y)),
				 EncodeCountColor(EncodeCount(EdgeCount.z, EdgeCount.w)));
}


//-----------------------------------------------------------------------------	
//	Main function used in third and final phase of the algorithm
//	This code reads previous inputs and perform anti-aliasing of edges by 
//  blending colors as required.
//-----------------------------------------------------------------------------
void BlendColor(Texture2D<float4> txImage, 
                UINT count,
                int2 pos, 
                int2 dir, 
                int2 ortho, 
                bool inverse, 
                in out float4 color)
{
    // Only process pixel edge if it contains a stop bit
	FLATTEN
	if ( IsBitSet(count, kStopBit_BitPosition+kPosCountShift) || IsBitSet(count, kStopBit_BitPosition+kNegCountShift) )  
	{
		// Retrieve edge length
		UINT negCount = DecodeCountNoStopBit(count, kNegCountShift);
		UINT posCount = DecodeCountNoStopBit(count, kPosCountShift);                              
        
		// Fetch color adjacent to the edge
		float4 adjacentcolor = txImage.Load(int3(pos+dir, 0));				        				
        
		FLATTEN
		if ( (negCount + posCount) == 0)
		{
			float weight = 1.0/8.0; // Arbitrary			
			// Cheap approximation of gamma to linear and then back again
			color.xyz = sqrt( lerp(color.xyz*color.xyz, adjacentcolor.xyz*adjacentcolor.xyz, weight) );																		
			return;
		}
		else
		{			
			// If no sign bit is found on either edge then artificially increase the edge length so that
			// we don't start anti-aliasing pixels for which we don't have valid data.
			if ( !(IsBitSet(count, (kStopBit_BitPosition+kPosCountShift)))) posCount = kMaxEdgeLength+1;
			if ( !(IsBitSet(count, (kStopBit_BitPosition+kNegCountShift)))) negCount = kMaxEdgeLength+1;
			
			// Calculate some variables
			float length = negCount + posCount + 1;
			float midPoint = (length)/2;
			float distance = (float)negCount;
            
			static const UINT upperU   = 0x00;
			static const UINT risingZ  = 0x01;
			static const UINT fallingZ = 0x02;
			static const UINT lowerU   = 0x03;

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

			UINT shape = 0x00;			
			FLATTEN
    		if (CompareColors( (txImage.Load(int3(pos-(ortho*negCount.xx), 0)).a), (txImage.Load(int3(pos-(ortho*(negCount.xx+1)), 0)).a) ))
			{
				shape |= risingZ;                
			}		
			FLATTEN
			if (CompareColors( (txImage.Load(int3(pos+(ortho*posCount.xx), 0)).a), (txImage.Load(int3(pos+(ortho*(posCount.xx+1)), 0)).a) ))			
			{
				shape |= fallingZ;                
			}
    		// Parameter "inverse" is hard-coded on call so will not generate a dynamic branch condition
			FLATTEN
			if (    (  inverse && ( ( (shape == fallingZ) && (float(negCount) <= midPoint) ) ||
									( (shape == risingZ)  && (float(negCount) >= midPoint) ) ||
									( (shape == upperU)                             ) ) ) 
				 || ( !inverse && ( ( (shape == fallingZ) && (float(negCount) >= midPoint) ) ||
									( (shape == risingZ)  && (float(negCount) <= midPoint) ) ||
									( (shape == lowerU)                             ) ) ) )
			{				
				float h0 = abs( (1.0/length) * (length-distance)     - 0.5);
				float h1 = abs( (1.0/length) * (length-distance-1.0) - 0.5);
				float area = 0.5 * (h0+h1);								
				// Cheap approximation of gamma to linear and then back again
				color.xyz = sqrt( lerp(color.xyz*color.xyz, adjacentcolor.xyz*adjacentcolor.xyz, area) );																								
			}
		}
    }
}


//-----------------------------------------------------------------------------
//	MLAA pixel shader for color blending.
//	Pixel shader used in third and final phase of the algorithm
//-----------------------------------------------------------------------------
// float4 MLAA_BlendColor_PS( ScreenQuad_OUTPUT In) : SV_TARGET
// {
// 	int2 TextureSize = _ScreenParams.xy - 1;
// 	int2 Offset = In.TextureUV*_ScreenParams.xy;	
// 		
//     UINT hcount, vcount;
// 	UINT hcountup, vcountright;
// 	
// 	UINT2(hcount, vcount) = DecodeCountColor2(g_txEdgeCount.Load(int3(Offset, 0)).xy);
// 	hcountup    = DecodeCountColor(g_txEdgeCount.Load(int3(Offset-kUp.xy, 0)).x);
// 	vcountright = DecodeCountColor(g_txEdgeCount.Load(int3(Offset-kRight.xy, 0)).y);
// 		
// 	// Retrieve pixel from original image
// 	float4 rVal = g_txSceneColor.Load(int3(Offset, 0));                   		
// 	// Blend pixel colors as required for anti-aliasing edges
// 	BRANCH if (hcount)		BlendColor(g_txSceneColor, hcount,      Offset,			 kUp,		kRight, false, rVal);   // H down-up
// 	BRANCH if (hcountup)	BlendColor(g_txSceneColor, hcountup,    Offset-kUp,		-kUp,		kRight, true,  rVal);   // H up-down    				    
// 	BRANCH if (vcount)		BlendColor(g_txSceneColor, vcount,      Offset,			 kRight,	kUp,    false, rVal);   // V left-right				
// 	BRANCH if (vcountright)	BlendColor(g_txSceneColor, vcountright, Offset-kRight,	-kRight,	kUp,    true,  rVal);   // V right-left    			
// 	        
// 	return rVal;
// }

float4 PS(Vertex_Output pin) : SV_Target
{
	uint2 auLineL = MLAA_ComputeLineLength(pin.TexC);;
	return UINT4_to_FLOAT4_D3DX_B8G8R8A8_UNORM(uint4(auLineL, 0, 0));
}
