﻿Shader "GC/GTAO"
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

            float GetH(float3 fragViewPos, float fragDepth, float2 uv, float2 marchingDir)
            {
                float depth;
                float3 normal;
                float nearest = fragDepth;
                float2 nearestuv = uv;
                for(int i = 0 ; i < _marchingCount ; i++)
                {
                    float2 newuv = uv + i * marchingDir * _CameraDepthNormalsTexture_TexelSize;
                    GetDepthNormal(newuv, depth, normal);
                    float w = depth > nearest ? 1 : 0;
                    nearest = lerp(nearest, depth, w);
                    nearestuv = lerp(nearestuv, newuv, w);
                }

                float nearestPos = ReconstructViewPos(nearestuv, nearest);
                float3 dir = normalize(nearestPos - fragViewPos);
                return abs(nearest - fragDepth) < 0.00001 ? UNITY_PI/2 : acos(abs(dir.z));
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

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);

                float depth;
                float3 normal;
                GetDepthNormal(i.uv, depth, normal);
                float3 viewPos = ReconstructViewPos(i.uv, depth);

                float totalD = 0;
                float count = 64.0;
                float n = acos(normal.z);
                for(int j = 0 ; j < count; j++)
                {
                    float radian = 2 * UNITY_PI * (j / count);
                    float2 dir = float2(cos(radian) , sin(radian));
                    //dir += rand(i.uv);
                    //dir = rand2dTo2d(dir + i.uv *50);
                    dir = normalize(dir);
                    float h1 = GetH(viewPos, depth, i.uv, dir);
                    float h2 = GetH(viewPos, depth, i.uv, -dir);
                    float ao = GetAO(h1, h2, n);
                    totalD += ao;
                }
                totalD /=  count;

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
