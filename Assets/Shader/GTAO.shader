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

            float _marchingRadius;
            int _marchingCount;
            float4 _marchingDir;

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

            float GetH(float3 fragViewPos, float2 uv, float2 marchingDir)
            {
                float depth;
                float3 normal;
                float stepSize = _marchingRadius / _marchingCount;
                float nearest = 0;
                float2 nearestuv = float2(0, 0);
                for(int i = 0 ; i < _marchingCount ; i++)
                {
                    float2 newuv = uv + i * stepSize * marchingDir;
                    GetDepthNormal(newuv, depth, normal);
                    float w = depth > nearest ? 1 : 0;
                    nearest = lerp(nearest, depth, w);
                    nearestuv = lerp(nearestuv, newuv, w);
                }

                return nearest;
                float nearestPos = ReconstructViewPos(nearestuv, nearest);
                float3 dir = normalize(nearestPos - fragViewPos);
                return acos(abs(dir.z));
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);

                float depth;
                float3 normal;
                GetDepthNormal(i.uv, depth, normal);
                float3 viewPos = ReconstructViewPos(i.uv, depth);

                float h1 = GetH(viewPos, i.uv, _marchingDir.xy);
                float h2 = GetH(viewPos, i.uv, -_marchingDir.xy);

#if _RAW_IMG
				return col;
#elif _ONLY_AO
				return (h1 - depth) * 100;
#elif _WITH_AO
				return col * h1;
#endif
            }
            ENDCG
        }
    }
}
