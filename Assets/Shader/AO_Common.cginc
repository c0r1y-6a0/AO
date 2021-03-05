void GetDepthNormal(float2 uv, out float depth, out float3 normal)
{
    float4 depthnormal = tex2Dlod(_CameraDepthNormalsTexture, float4(uv, 0, 0));
    DecodeDepthNormal(depthnormal, depth, normal);
}

float3 ReconstructViewPos(float2 uv, float linear01Depth)
{
    float2 NDC = uv * 2 - 1;
    float3 clipVec = float3(NDC.x, NDC.y, 1.0) * _ProjectionParams.z;
    float3 viewVec = mul(invproj, clipVec.xyzz).xyz;
    return viewVec * linear01Depth;
}

float4 _SSAO_UVToView;
inline half3 GetPosition(half2 uv)
{
    float viewDepth;
    float3 _;
    GetDepthNormal(uv, viewDepth, _);
    return half3( (uv * _SSAO_UVToView.xy + _SSAO_UVToView.zw) * viewDepth, viewDepth );
}

float3 GetViewPos(float2 uv)
{
    float depth;
    float3 _;
    GetDepthNormal(uv, depth, _);
    return ReconstructViewPos(uv, depth);
}

inline half Rand(half3 position)
{
    return frac(dot(position, half3( 0.6711056, 0.0583715, 0.1355213))* 52.9829189);
}

inline half Rand(half2 position)
{
    return frac(dot(position, half2( 0.6711056, 0.0583715)) * 52.9829189);
}

float TanToSin(float x)
{
    return x * rsqrt(x*x + 1.0);
}

float InvLength(float2 V)
{
    return rsqrt(dot(V,V));
}

float Tangent(float3 V)
{
    return V.z * InvLength(V.xy);
}

float _bias;
float BiasedTangent(float3 V)
{
    return V.z * InvLength(V.xy) + tan(30.0 * _bias/ 180.0);
}

float Tangent(float3 P, float3 S)
{
    return -(P.z - S.z) * InvLength(S.xy - P.xy);
}

float Length2(float3 V)
{
    return dot(V,V);
}

float3 MinDiff(float3 P, float3 Pr, float3 Pl)
{
    float3 V1 = Pr - P;
    float3 V2 = P - Pl;
    return (Length2(V1) < Length2(V2)) ? V1 : V2;
}

float2 SnapUVOffset(float2 uv)
{
    return round(uv * _ScreenParams.xy) * (_ScreenParams.zw - 1);
}

float4 SnapUVOffset(float4 uv)
{
    return round(uv * _ScreenParams.xyxy) * (_ScreenParams.zwzw - 1);
}

float Falloff(float d2)
{
    return d2 * (-1 / (_radius * _radius)) + 1.0f;
}