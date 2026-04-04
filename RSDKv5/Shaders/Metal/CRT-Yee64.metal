// CRT-Yee64.metal — higher-quality CRT with multi-sample horizontal phosphor blending.

#define viewSizeHD  720.0
#define intencity   float3(1.2, 0.9, 0.9)
#define brightness  1.25

fragment float4 fragment_main(RSDKVarying         in   [[stage_in]],
                              texture2d<float>    tex  [[texture(0)]],
                              sampler             samp [[sampler(0)]],
                              constant RSDKUniforms &u [[buffer(0)]])
{
    float2 texelPos = (u.textureSize / u.pixelSize) * in.texCoord;
    float4 size     = (u.pixelSize / u.textureSize).xyxy * texelPos.xyxy;
    float2 ex       = size.zw * u.textureSize - floor(size.zw * u.textureSize) - 0.5;

    float4 factor = pow(float4(2.0),
                        pow(float4(-1., 1., -2., 2.) - ex.x, float4(2.0)) * -3.0);
    float factor2 = pow(2.0, pow(ex.x, 2.0) * -3.0);

    float3 power;
    power.x = pow(2.0, pow(  ex.y,        2.0) * -8.0);
    power.y = pow(2.0, pow(-1.0 - ex.y,   2.0) * -8.0);
    power.z = pow(2.0, pow( 1.0 - ex.y,   2.0) * -8.0);

    float2 vp      = floor(texelPos * u.viewSize) + 0.5;
    float  iPos    = fract((vp.y * 3.0 + vp.x) * (1.0 / 6.0));

    float4 scanCol;
    if (iPos < (1.0 / 3.0))      scanCol.rgb = intencity.xyz;
    else if (iPos < (2.0 / 3.0)) scanCol.rgb = intencity.zxy;
    else                          scanCol.rgb = intencity.yzx;

    // 11-sample horizontal phosphor blur
#define S(off) tex.sample(samp, (floor(size.zw * u.textureSize + (off)) + 0.5) / u.textureSize).rgb

    float3 c1  = S(float2( 1., -1.)) * factor.y  * brightness;
    float3 c2  = S(float2(-2.,  0.)) * factor.z  * brightness;
    float3 c3  = S(float2(-1.,  0.)) * factor.x  * brightness;
    float3 c4  = S(float2( 1.,  0.)) * factor.y  * brightness;
    float3 c5  = S(float2( 0.,  0.)) * factor2   * brightness;
    float3 c6  = S(float2(-1.,  1.)) * factor.x  * brightness;
    float3 c7  = S(float2( 2.,  0.)) * factor.w  * brightness;
    float3 c8  = S(float2(-1., -1.)) * factor.x  * brightness;  // "-1" → float2(-1,-1)
    float3 c9  = S(float2( 0., -1.)) * factor2   * brightness;
    float3 c10 = S(float2( 1.,  1.)) * factor.y  * brightness;
    float3 c11 = S(float2( 0.,  1.)) * factor2   * brightness;  // uses size.xy base

    // c11 uses size.xy intentionally (original shader does this)
    c11 = tex.sample(samp, (floor(size.xy * u.textureSize + float2(0., 1.)) + 0.5) / u.textureSize).rgb
          * factor2 * brightness;

#undef S

    float3 final =
        (c2 + c3 + c4 + c5 + c7) / (factor.z + factor.x + factor.y + factor2 + factor.w) * power.x +
        (c1 + c8 + c9)           / (factor.y + factor.x + factor2)                        * power.y +
        (c10 + c6 + c11)         / (factor.y + factor.x + factor2)                        * power.z;

    float4 out;
    out.rgb = (viewSizeHD < u.viewSize.y) ? (scanCol.rgb * final) : final;
    out.rgb *= u.screenDim;
    out.a    = 1.0;
    return out;
}
