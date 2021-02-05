﻿Shader "GC/SSAO"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

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
            float4 _MainTex_ST;

            sampler2D _CameraDepthNormalsTexture;

            #define KERNEL_MAX_SIZE 64
            int kernel_size;
            float4 kernel[KERNEL_MAX_SIZE];
            float radius;
            float4x4 invproj;
            float4x4 projection;

            sampler2D _NoiseTex;
            float noiseSize;

            float bias;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            void GetDepthNormal(float2 uv,out float depth, out float3 normal)
            {
			    float4 depthnormal = tex2D(_CameraDepthNormalsTexture, uv);
                DecodeDepthNormal(depthnormal, depth, normal);
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);
                float3 normal;
                float depth;
                GetDepthNormal(i.uv, depth, normal);

                float2 NDC = i.uv * 2 - 1;
                float3 clipVec = float3(NDC.x, NDC.y, 1.0) * _ProjectionParams.z;
                float3 viewVec = mul(invproj, clipVec.xyzz).xyz;
                float3 viewPos = viewVec * depth;
				float viewZ = depth * -_ProjectionParams.z;

                /* 
                //for debug
                float4 clipPos = mul(projection, float4(viewPos, 1.0));
                float3 ndcPos = clipPos.xyz / clipPos.w;
                return float4(ndcPos.xy * 0.5 + 0.5, 0, 1);
                float u = clipPos.x / -clipPos.w;// *0.5 + 0.5;
                float v = clipPos.y / -clipPos.w;// *0.5 + 0.5;
                return float4(u, v, 0, 0);
                */

                float2 noiseScale = float2(_ScreenParams.x / noiseSize, _ScreenParams.y / noiseSize);
                float3 randomVec = tex2D(_NoiseTex, i.uv * noiseScale).xyz;
                randomVec = float3(randomVec.x * 2.0 - 1.0, randomVec.y * 2.0 - 1.0, randomVec.z);
                float3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
                float3 bitangent = cross(normal, tangent);
                float3x3 tbn = float3x3(
                    tangent.x, bitangent.x, normal.x,
                    tangent.y, bitangent.y, normal.y,
                    tangent.z, bitangent.z, normal.z
                    );


                float occulision = 0;
                float sampleDepth = 0;
                float3 sampleNormal = 0;


                for (int i = 0; i < kernel_size; i++)
                {
                    float3 offset = mul(tbn, kernel[i].xyz);
                    float3 samplePos = viewPos + offset * radius;
                    float4 pos = float4(samplePos, 1.0f);
                    pos = mul(projection, pos);
                    float2 uv = pos.xy / pos.w;
                    uv = uv * 0.5 + 0.5;
                    GetDepthNormal(uv, sampleDepth, sampleNormal);

                    float sampleZ = sampleDepth * -_ProjectionParams.z;
                    float rangeCheck = smoothstep(0.0, 1.0, radius / abs(viewZ - sampleZ));
                    occulision += ((sampleZ >= (samplePos.z + bias)) ? 1.0 : 0.0) *rangeCheck;
                }

                occulision = 1.0 - occulision / kernel_size;

#if _RAW_IMG
                return col;
#elif _ONLY_AO
                return occulision;
#elif _WITH_AO
                return col * occulision;
#endif
            }
            ENDCG
        }
    }
}
