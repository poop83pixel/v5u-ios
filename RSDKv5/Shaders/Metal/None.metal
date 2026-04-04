// None.metal — pixel-perfect display with sub-pixel smoothing at non-integer scales.
// Compiled at runtime by MetalShaders_Load; the vertex_main / struct header
// is prepended by SDL2MetalShaders.mm before compilation.

fragment float4 fragment_main(RSDKVarying         in       [[stage_in]],
                              texture2d<float>    tex      [[texture(0)]],
                              sampler             samp     [[sampler(0)]],
                              constant RSDKUniforms &u     [[buffer(0)]])
{
    float2 uv = in.texCoord;

    // Check whether the viewport is an integer multiple of pixelSize.
    float2 viewScale;
    viewScale.x = fract(u.viewSize.x / u.pixelSize.x) - 0.01;
    viewScale.y = fract(u.viewSize.y / u.pixelSize.y) - 0.01;

    if (viewScale.x < 0.0 && viewScale.y < 0.0) {
        // Exact integer scale — sample directly, no filtering needed.
        return tex.sample(samp, uv) * u.screenDim;
    }

    // Non-integer scale: manual bilinear over texel boundaries so we don't
    // get shimmer from the hardware point-sampler.
    float2 adjacent;
    adjacent.x = abs(dfdx(uv.x));
    adjacent.y = abs(dfdy(uv.y));

    float4 texPos;
    texPos.zw = adjacent.yx * 0.500501 + uv.yx;
    texPos.xy = -adjacent.xy * 0.500501 + uv.xy;

    float2 texelSize = 1.0 / u.textureSize.yx;
    float2 texCoord  = clamp(texelSize.xy * round(uv.yx / texelSize.xy), texPos.yx, texPos.zw);

    float4 blendFactor;
    blendFactor.xy = -texPos.xy + texCoord.yx;
    blendFactor.zw =  texPos.zw - texCoord.xy;

    float strength = adjacent.x * adjacent.y * 0.500501 * 2.002;

    float4 blend;
    blend.x = (blendFactor.x * blendFactor.y) / strength;
    blend.y = (blendFactor.z * blendFactor.w) / strength;
    blend.z = (blendFactor.z * blendFactor.x) / strength;
    blend.w = (blendFactor.w * blendFactor.y) / strength;

    float4 color =
        tex.sample(samp, texPos.xy) * blend.x +
        tex.sample(samp, texPos.wz) * blend.y +
        tex.sample(samp, texPos.xz) * blend.z +
        tex.sample(samp, texPos.wy) * blend.w;

    color.rgb *= u.screenDim;
    return color;
}
