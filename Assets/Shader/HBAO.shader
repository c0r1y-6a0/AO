Shader "GC/HBAO"
{
    Properties
    {

    }

    SubShader
    {
        ZTest Always
        Cull Off
        ZWrite Off

        Pass
        { 
            CGPROGRAM 
            #include "UnityCG.cginc"

            #pragma vertex vert
            #pragma fragment frag

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
            sampler2D _CameraDepthNormalsTexture;
            float4 _CameraDepthNormalsTexture_TexelSize;

            int NumSamples;
            int NumDirections;
            float _radius;

            float4x4 invproj;

            #include "AO_Common.cginc"

            /*
            uniform float2 AORes =_ScreenParams.xy;
            uniform float2 InvAORes = float2(1.0/1024.0, 1.0/768.0);
            uniform float2 NoiseScale = float2(1024.0, 768.0) / 4.0;
            */

            uniform float AOStrength;
            uniform float MaxRadiusPixels;


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float HorizonOcclusion(float2 uv, float2 deltaUV, float3 P, float3 dPdu, float3 dPdv, float randstep, float numSamples)
            {
                float ao = 0;

                // Offset the first coord with some noise
                uv = uv + SnapUVOffset(randstep*deltaUV);
                deltaUV = SnapUVOffset( deltaUV );

                // Calculate the tangent vector
                float3 T = deltaUV.x * dPdu + deltaUV.y * dPdv;

                // Get the angle of the tangent vector from the viewspace axis
                float tanH = BiasedTangent(T);
                float sinH = TanToSin(tanH);

                float tanS;
                float d2;
                float3 S;

                // Sample to find the maximum angle
                for(float s = 1; s <= numSamples; ++s)
                {
                    uv += deltaUV;
                    S = GetViewPos(uv);
                    tanS = Tangent(P, S);
                    d2 = Length2(S - P);

                    // Is the sample within the radius and the angle greater?
                    if(d2 < _radius * _radius && tanS > tanH)
                    {
                        float sinS = TanToSin(tanS);
                        // Apply falloff based on the distance
                        ao += Falloff(d2) * (sinS - sinH);

                        tanH = tanS;
                        sinH = sinS;
                    }
                }
                
                return ao;
            }


            float2 RotateDirections(float2 Dir, float2 CosSin)
            {
                return float2(Dir.x*CosSin.x - Dir.y*CosSin.y, Dir.x*CosSin.y + Dir.y*CosSin.x);
            }

            inline float2 InvAORes()
            {
                return _ScreenParams.zw - 1.0;
            }

            void ComputeSteps(inout float2 stepSizeUv, inout float numSteps, float rayRadiusPix, float rand)
            {
                // Avoid oversampling if numSteps is greater than the kernel radius in pixels
                numSteps = min(NumSamples, rayRadiusPix);

                // Divide by Ns+1 so that the farthest samples are not fully attenuated
                float stepSizePix = rayRadiusPix / (numSteps + 1);

                // Clamp numSteps if it is greater than the max kernel footprint
                float maxNumSteps = MaxRadiusPixels / stepSizePix;
                if (maxNumSteps < numSteps)
                {
                    // Use dithering to avoid AO discontinuities
                    numSteps = floor(maxNumSteps + rand);
                    numSteps = max(numSteps, 1);
                    stepSizePix = MaxRadiusPixels / numSteps;
                }

                // Step size in uv space
                stepSizeUv = stepSizePix * InvAORes();
            }



            half4 frag(v2f i) : SV_TARGET
            {
                float numDirections = NumDirections;
                float2 AORes = _ScreenParams.xy;

                float3 P, Pr, Pl, Pt, Pb;
                P 	= GetViewPos(i.uv);

                // Sample neighboring pixels
                Pr 	= GetViewPos(i.uv + float2( InvAORes().x, 0));
                Pl 	= GetViewPos(i.uv + float2(-InvAORes().x, 0));
                Pt 	= GetViewPos(i.uv + float2( 0, InvAORes().y));
                Pb 	= GetViewPos(i.uv + float2( 0,-InvAORes().y));

                // Calculate tangent basis vectors using the minimu difference
                float3 dPdu = MinDiff(P, Pr, Pl);
                float3 dPdv = MinDiff(P, Pt, Pb) * (AORes.y * InvAORes().x);

                // Get the random samples from the noise texture
                float3 random = float3(Rand(P), Rand(P * 0.1), Rand(P * 20));

                float t = unity_CameraProjection._m11;
                float half_fov = atan(1.0f / t );
                float2 FocalLen = float2( 1.0 / tan(half_fov) * (_ScreenParams.y / _ScreenParams.x), 1.0 / tan(half_fov));

                // Calculate the projected size of the hemisphere
                float2 rayRadiusUV = 0.5 * _radius * FocalLen / -P.z;
                float rayRadiusPix = rayRadiusUV.x * AORes.x;

                float ao = 1.0;

                // Make sure the radius of the evaluated hemisphere is more than a pixel
                if(rayRadiusPix > 1.0)
                {

                    ao = 0.0;
                    float numSteps;
                    float2 stepSizeUV;

                    // Compute the number of steps
                    ComputeSteps(stepSizeUV, numSteps, rayRadiusPix, random.z);

                    // Calculate the horizon occlusion of each direction
                    for(float d = 0; d < numDirections; ++d)
                    {
                        float theta = 2.0 * UNITY_PI / numDirections * d;

                        // Apply noise to the direction
                        float2 dir = RotateDirections(float2(cos(theta), sin(theta)), random.xy);
                        float2 deltaUV = dir * stepSizeUV;

                        // Sample the pixels along the direction
                        ao += HorizonOcclusion(i.uv, deltaUV, P, dPdu, dPdv, random.z, numSteps);
                    }
                    // Average the results and produce the final AO
                    ao = 1.0 - ao / numDirections * AOStrength;
                }

                return ao;
            }
            ENDCG
        }

        Pass
        { 
            CGPROGRAM 
            #include "UnityCG.cginc"

            #pragma vertex vert
            #pragma fragment frag

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
            sampler2D _CameraDepthNormalsTexture;
            float4 _CameraDepthNormalsTexture_TexelSize;

            int NumDirections;
            int NumSamples;
            float _radius;
            uniform float AOStrength;
            uniform float MaxRadiusPixels;

            float4x4 invproj;

            #include "AO_Common.cginc"

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float mySign(float v)
            {
                float sT = sign(v);
                sT = sT == 0 ? 1 : -1;
                return sT;
            }

            float HBAO(float2 uv, out float3 debugNormal)
            {
                float depth;
                float3 normal;
                GetDepthNormal(uv, depth, normal);
                float3 viewPos = ReconstructViewPos(uv, depth);
                float3 viewDir = normalize(-viewPos);

                float3 dx = ddx(viewPos);
                float3 dy  = ddy(viewPos);
                float3 faceNormal = normalize(-cross(dx, dy));
                debugNormal = faceNormal;

                float tangentT = 1 / Tangent(normal);
                //float sinT = TanToSin(tangentT);
                float sinT = length(normal.xy);

                //float sT = -mySign(faceNormal.z);
                //float sinT = sT * length(faceNormal.xy) + sin(_bias/4);

                float angleNoise = Rand(viewPos * 10);

                float ao = 0;
                UNITY_LOOP
                for(int i = 0 ; i < NumSamples ; i++)
                {
                    float angle = UNITY_PI * 2 / NumSamples * i + angleNoise;
                    float3 marchDir = float3(cos(angle), sin(angle), 0);

                    float dirAO = 0;
                    UNITY_LOOP
                    for(int j = 0 ; j < NumDirections ; j++)
                    {
                        float2 deltaUV = (j + 1) * marchDir * _CameraDepthNormalsTexture_TexelSize * (NumDirections / (NumDirections + 1.0));
                        deltaUV = SnapUVOffset(deltaUV);
                        float2 marchingUV = SnapUVOffset(uv + deltaUV);
                        float marchingDepth; 
                        float3 _;
                        GetDepthNormal(marchingUV, marchingDepth, _);
                        float3 marchingPos = ReconstructViewPos(marchingUV, marchingDepth);
                        float3 marchingVec = marchingPos - viewPos;
                        float tangentH = Tangent(marchingVec);
                        float d2 = Length2(marchingVec);
                        if(length(marchingVec) < _radius && tangentH > tangentT)
                        {
                            float sinH = TanToSin(tangentH);
                            // Apply falloff based on the distance
                            dirAO += Falloff(d2) * (sinH - sinT);

                            tangentT = tangentH;
                            sinT = sinH;
                        }
                    }
                    ao += dirAO;
                }

                ao = 1.0 - ao / NumDirections * AOStrength;
                return ao;
            }

            half4 frag(v2f i) : SV_TARGET
            {
                fixed4 col = tex2D(_MainTex, i.uv);

                float3 debugNormal;
                float ao = HBAO(i.uv, debugNormal);
                // return float4(debugNormal, 0);
                return ao;
            }

            ENDCG
        }
    }
}
