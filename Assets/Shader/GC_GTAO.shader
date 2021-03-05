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
            #include "Filter.hlsl"

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
            float _SSAO_HalfProjScale;

            float4x4 invproj;

            #include "AO_Common.cginc"

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
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

            half IntegrateArc_CosWeight(half2 h, half n)
            {
                half2 Arc = -cos(2 * h - n) + cos(n) + 2 * h * sin(n);
                return 0.25 * (Arc.x + Arc.y);
            }

            half IntegrateArc_UniformWeight(half2 h)
            {
                half2 Arc = 1 - cos(h);
                return Arc.x + Arc.y;
            }

            float3 GTAO(float2 uv)
            {
                float depth;
                float3 normal;
                GetDepthNormal(uv, depth, normal);
                float3 viewPos = GetPosition(uv);
                half3 viewDir = normalize(0 - viewPos);
                half noiseDirection = Rand(uv * _CameraDepthNormalsTexture_TexelSize.zw);

	            half stepRadius = (max(min((_radius * _SSAO_HalfProjScale) / viewPos.z, 512), (half)_marchingCount)) / ((half)_marchingCount + 1);

                float Occlusion = 0;
                UNITY_LOOP
                for(float i = 0 ; i < _scliceCount; i++)
                {
                    float radian =  (UNITY_PI / _scliceCount ) * (i + noiseDirection);
                    float3 dir = float3(cos(radian) , sin(radian), 0);
                    float planeNormal = normalize(cross(dir, viewDir));
                    float planeTangent = cross(viewDir, planeNormal);
                    float3 sliceNormal = normal - planeNormal * dot(normal, planeNormal);
                    float sliceLength = length(sliceNormal);

                    float cos_n = clamp(dot(normalize(sliceNormal), viewDir), -1, 1);
                    float n = -sign(dot(sliceNormal, planeTangent)) * acos(cos_n);

                    float2 h = -1;
                    UNITY_LOOP
                    for (int j = 0; j < _marchingCount; j++)
                    {
                        float2 uvOffset = (dir.xy * _CameraDepthNormalsTexture_TexelSize.xy) * (max(stepRadius * j, 1 + j));
                        float4 uvSlice = uv.xyxy + float4(uvOffset.xy, -uvOffset);

                        float3 h1 = GetPosition(uvSlice.xy) - viewPos;
                        float3 h2 = GetPosition(uvSlice.zw) - viewPos;

                        float2 h1h2 = float2(dot(h1, h1), dot(h2, h2));
                        float2 h1h2Length = rsqrt(h1h2);

                        float2 falloff = saturate(h1h2 * (2 / (_radius * _radius)));

                        float2 H = half2(dot(h1, viewDir), dot(h2, viewDir)) * h1h2Length;
                        h.xy = (H.xy > h.xy) ? lerp(H, h, falloff) : h.xy;
                    }

                    h = acos(clamp(h, -1, 1));
                    h.x = n + max(-h.x - n, -UNITY_HALF_PI);
                    h.y = n + min(h.y - n, UNITY_HALF_PI);

                    //Occlusion += sliceLength * IntegrateArc_CosWeight(h, n); 			
                    Occlusion += sliceLength * IntegrateArc_UniformWeight(h); 			
                }
                //Occlusion /=  _scliceCount;
                Occlusion = pow(Occlusion / _scliceCount, 2);
                return Occlusion;
            }


            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);
                float Occlusion = GTAO(i.uv);

                #ifdef _RAW_IMG
                    return col;
                #elif _ONLY_AO
                    return Occlusion;
                #elif _WITH_AO
                    return col * Occlusion;
                #endif
            }
            ENDCG
        }
    }
}
