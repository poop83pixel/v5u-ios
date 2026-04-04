// Clean.metal — sharp bilinear upscale that preserves pixel boundaries.

fragment float4 fragment_main(RSDKVarying         in   [[stage_in]],
                              texture2d<float>    tex  [[texture(0)]],
                              sampler             samp [[sampler(0)]],
                              constant RSDKUniforms &u [[buffer(0)]])
{
    float2 texel         = in.texCoord * u.textureSize;
    float2 texelFloored  = floor(texel);
    float2 s             = fract(texel);
    float2 regionRange   = 0.5 - 0.5 / float2(2.0);

    float2 centerDist = s - 0.5;
    float2 f          = (centerDist - clamp(centerDist, -regionRange, regionRange)) * 2.0 + 0.5;
    float2 modTexel   = texelFloored + f;

    float4 color = tex.sample(samp, modTexel / u.textureSize);
    color.rgb *= u.screenDim;
    return color;
}
