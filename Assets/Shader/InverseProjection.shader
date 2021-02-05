Shader "dd/Test/InverseProjection"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    CGINCLUDE
    #include "UnityCG.cginc"

    #define EXCLUDE_FAR_PLANE

    sampler2D _MainTex;
    sampler2D _CameraDepthNormalsTexture;

    half _Opacity;

    struct Varyings
    {
        float4 position : SV_Position;
        float2 texcoord : TEXCOORD0;
        float3 ray : TEXCOORD1;
    };

    // Vertex shader that procedurally outputs a full screen triangle
    Varyings Vertex(uint vertexID : SV_VertexID)
    {
        // Render settings
        float far = _ProjectionParams.z;
        float2 orthoSize = unity_OrthoParams.xy;
        float isOrtho = unity_OrthoParams.w; // 0: perspective, 1: orthographic

        // Vertex ID -> clip space vertex position
        float x = (vertexID != 1) ? -1 : 3;
        float y = (vertexID == 2) ? -3 : 1;
        float3 vpos = float3(x, y, 1.0);

        // Perspective: view space vertex position of the far plane
        float3 rayPers = mul(unity_CameraInvProjection, vpos.xyzz * far).xyz;

        // Orthographic: view space vertex position
        float3 rayOrtho = float3(orthoSize * vpos.xy, 0);

        Varyings o;
        o.position = float4(vpos.x, -vpos.y, 1, 1);
        o.texcoord = (vpos.xy + 1) / 2;
        o.ray = lerp(rayPers, rayOrtho, isOrtho);
        return o;
    }

    void GetDepthNormal(float2 uv, out float depth, out float3 normal)
    {
        float4 depthnormal = tex2D(_CameraDepthNormalsTexture, uv);
        DecodeDepthNormal(depthnormal, depth, normal);
    }

    float3 ComputeViewSpacePosition(Varyings input)
    {
        // Render settings
        float near = _ProjectionParams.y;
        float far = _ProjectionParams.z;
        float isOrtho = unity_OrthoParams.w; // 0: perspective, 1: orthographic

        // Z buffer sample
        float z;
        float3 p;
        GetDepthNormal(input.texcoord, z, p);


        // Far plane exclusion
        #if !defined(EXCLUDE_FAR_PLANE)
        float mask = 1;
        #elif defined(UNITY_REVERSED_Z)
        float mask = z > 0;
        #else
        float mask = z < 1;
        #endif

        // Perspective: view space position = ray * depth
        float3 vposPers = input.ray * z;

        // Orthographic: linear depth (with reverse-Z support)
        #if defined(UNITY_REVERSED_Z)
        float depthOrtho = -lerp(far, near, z);
        #else
        float depthOrtho = -lerp(near, far, z);
        #endif

        // Orthographic: view space position
        float3 vposOrtho = float3(input.ray.xy, depthOrtho);

        // Result: view space position
        return lerp(vposPers, vposOrtho, isOrtho) * mask;
    }

    half4 VisualizePosition(Varyings input, float3 pos)
    {
        const float grid = 5;
        const float width = 3;

        pos *= grid;

        // Detect borders with using derivatives.
        float3 fw = fwidth(pos);
        half3 bc = saturate(width - abs(1 - 2 * frac(pos)) / fw);

        // Frequency filter
        half3 f1 = smoothstep(1 / grid, 2 / grid, fw);
        half3 f2 = smoothstep(2 / grid, 4 / grid, fw);
        bc = lerp(lerp(bc, 0.5, f1), 0, f2);

        // Blend with the source color.
        half4 c = tex2D(_MainTex, input.texcoord);
        c.rgb = lerp(c, bc, 0.5);

        return c;
    }

    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            CGPROGRAM

            #pragma vertex Vertex
            #pragma fragment Fragment

            half4 Fragment(Varyings input) : SV_Target
            {
                float3 vpos = ComputeViewSpacePosition(input);
                return float4(vpos, 1);
                return VisualizePosition(input, vpos);
            }

            ENDCG
        }
        /*
        Pass
        {
            CGPROGRAM

            #pragma vertex Vertex
            #pragma fragment Fragment

            float4x4 _InverseView;

            half4 Fragment(Varyings input) : SV_Target
            {
                float3 vpos = ComputeViewSpacePosition(input);
                float3 wpos = mul(_InverseView, float4(vpos, 1)).xyz;
                return VisualizePosition(input, wpos);
            }

            ENDCG
        }
        */
    }
}
