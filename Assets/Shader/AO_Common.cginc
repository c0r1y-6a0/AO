void GetDepthNormal(float2 uv, out float depth, out float3 normal)
{
    float4 depthnormal = tex2D(_CameraDepthNormalsTexture, uv);
    DecodeDepthNormal(depthnormal, depth, normal);
}

float3 ReconstructViewPos(float2 uv, float linear01Depth)
{
    float2 NDC = uv * 2 - 1;
    float3 clipVec = float3(NDC.x, NDC.y, 1.0) * _ProjectionParams.z;
    float3 viewVec = mul(invproj, clipVec.xyzz).xyz;
    return viewVec * linear01Depth;
}