Shader "Unlit/radial_blur"
{
    Properties
    {
        _BlurSamples("Blur Sample Number", Int) = 10
        _BlurRadius("Blur Sample Radius", Range(0, 0.5)) = 0.1
        _BlurCenter("Blur Center", Vector) = (0.5, 0.5, 0.5, 0.5)
        _BlurPower("Blur Power", Float) = 3
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

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
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            int _BlurSamples;
            float _BlurRadius;
            float _BlurPower;
            float4 _BlurCenter;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                return Radial(_MainTex, i.uv, _BlurSamples, _BlurRadius, _BlurCenter, _BlurPower);
            }
            ENDCG
        }
    }
}
