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

        #include "UnityCG.cginc"
        #include "AO_Common.cginc"

        #pragma vertex vert
        #pragma fragment frag

        Pass
        { 
            CGPROGRAM 

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

            ENDCG
        }
    }
}