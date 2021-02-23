Shader "GC/GTAO"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.0
            #pragma multi_compile _RAW_IMG _ONLY_AO _WITH_AO

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
            sampler2D _CameraDepthNormalsTexture;
            float4 _CameraDepthNormalsTexture_TexelSize;

            int _marchingCount;
            int _scliceCount;
            float _radius;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            void GetDepthNormal(float2 uv, out float depth, out float3 normal)
            {
                float4 depthnormal = tex2D(_CameraDepthNormalsTexture, uv);
                DecodeDepthNormal(depthnormal, depth, normal);
            }

            float4x4 invproj;
            float3 ReconstructViewPos(float2 uv, float linear01Depth)
            {
                float2 NDC = uv * 2 - 1;
                float3 clipVec = float3(NDC.x, NDC.y, 1.0) * _ProjectionParams.z;
                float3 viewVec = mul(invproj, clipVec.xyzz).xyz;
                return viewVec * linear01Depth;
            }

            inline half Rand(half2 position)
            {
                return frac(frac(dot(position, half2( 0.06711056, 0.00583715))) * 52.9829189 );
            }

            float GetH(float3 fragViewPos, float fragDepth, float2 uv, float2 marchingDir, float3 viewDir)
            {
                float depth;
                float3 normal;
                float max_cos = -1;
                for(int i = 0 ; i < _marchingCount ; i++)
                {
                    float2 newuv = uv + (i + 1) * marchingDir.xy * _CameraDepthNormalsTexture_TexelSize.xy;
                    GetDepthNormal(newuv, depth, normal);
                    float3 pos = ReconstructViewPos(newuv, depth);
                    float3 dir = pos - fragViewPos;
                    float cos_d = dot(dir, viewDir);
                    float l = length(dir);
                    cos_d = l < 0.0000001 ? -1 : cos_d / l;

                    float falloff = l * 2 / _radius * _radius;
                    max_cos = cos_d > max_cos ? lerp(cos_d, max_cos, falloff) : max_cos;
                }

                return acos(clamp(max_cos, -1, 1));
            }

            float GetAOInner(float h, float n)
            {
                return -cos(2 * h - n) + cos(n) + 2 * h * sin(n);
            }

            float GetAO(float h1, float h2, float n)
            {
                //return 2 - cos(h1) - cos(h2);
                float v1 = GetAOInner(h1, n);
                float v2 = GetAOInner(h2, n);
                return (v1 + v2) * 0.25;
            }

            float2 rand(float2 value)
            {
                return frac(sin(value) * 15213.331);
            }

            float3 GetPosition(float2 uv)
            {
                float depth;
                float3 normal;
                GetDepthNormal(uv, depth, normal);
                return ReconstructViewPos(uv, depth);
            }

            half IntegrateArc_CosWeight(half2 h, half n)
            {
                half2 Arc = -cos(2 * h - n) + cos(n) + 2 * h * sin(n);
                return 0.25 * (Arc.x + Arc.y);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);

                float depth;
                float3 normal;
                GetDepthNormal(i.uv, depth, normal);
                float3 viewPos = ReconstructViewPos(i.uv, depth);
                half3 viewDir = normalize(0 - viewPos);
                half noiseDirection = Rand(i.uv * _CameraDepthNormalsTexture_TexelSize.zw);

                float totalD = 0;
                float2 h, H, uvOffset, h1h2, h1h2Length, falloff;
                float4 uvSlice;
                float h1, h2;
                UNITY_LOOP
                for(float j = 0 ; j < _scliceCount; j++)
                {
                    float radian =  (UNITY_PI / _scliceCount ) * (j + 1 );//+ noiseDirection);
                    float3 dir = float3(cos(radian) , sin(radian), 0);
                    float planeNormal = normalize(cross(dir, viewDir));
                    float planeTangent = cross(viewDir, planeNormal);
                    float3 sliceNormal = normal - planeNormal * dot(normal, planeNormal);
                    float sliceLength = length(sliceNormal);

                    float cos_n = clamp(dot(normalize(sliceNormal), viewDir), -1, 1);
                    float n = -sign(dot(sliceNormal, planeTangent)) * acos(cos_n);

                    /*
                    float h1 = -GetH(viewPos, depth, i.uv, dir.xy, viewDir);
                    float h2 = GetH(viewPos, depth, i.uv, -dir.xy, viewDir);

                    h1 = n + max(h1 - n, -UNITY_HALF_PI);
                    h2 = n + min(h2 - n, UNITY_HALF_PI);
                    float ao = GetAO(h1, h2, n);
                    totalD += sliceLength * ao;
                    */

                    h = -1;

                    UNITY_LOOP
                    for (int j = 0; j < _marchingCount; j++)
                    {
                        uvOffset = (dir.xy * _CameraDepthNormalsTexture_TexelSize.xy) * (1 + j);
                        uvSlice = i.uv.xyxy + float4(uvOffset.xy, -uvOffset);

                        h1 = GetPosition(uvSlice.xy) - viewPos;
                        h2 = GetPosition(uvSlice.zw) - viewPos;

                        h1h2 = half2(dot(h1, h1), dot(h2, h2));
                        h1h2Length = rsqrt(h1h2);

                        falloff = saturate(h1h2 * (2 / (_radius * _radius)));

                        H = half2(dot(h1, viewDir), dot(h2, viewDir)) * h1h2Length;
                        h.xy = (H.xy > h.xy) ? lerp(H, h, falloff) : h.xy;
                    }

                    h = acos(clamp(h, -1, 1));
                    h.x = n + max(-h.x - n, -UNITY_HALF_PI);
                    h.y = n + min(h.y - n, UNITY_HALF_PI);

                    totalD += sliceLength * IntegrateArc_CosWeight(h, n); 			
                }
                //totalD /=  _scliceCount;
                totalD = pow(totalD / _scliceCount, 2);

                #ifdef _RAW_IMG
                    return col;
                #elif _ONLY_AO
                    return totalD;
                #elif _WITH_AO
                    return col * totalD;
                #endif
            }
            ENDCG
        }
    }
}
