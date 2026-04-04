// YUV-422.metal — YCbCr 4:2:2 decode.
// Chroma is sub-sampled horizontally only; sample U/V at half the U coord.

fragment float4 fragment_main(RSDKVarying         in   [[stage_in]],
                              texture2d<float>    tex  [[texture(0)]],
                              sampler             samp [[sampler(0)]],
                              constant RSDKUniforms &u [[buffer(0)]])
{
    float2 chromaUV = float2(in.texCoord.x * 0.5, in.texCoord.y);
    chromaUV        = clamp(chromaUV, 0.0, 0.499);

    float3 yuv;
    yuv.r  = tex.sample(samp, in.texCoord).r;
    yuv.gb = tex.sample(samp, chromaUV).gb;
    yuv   -= float3(16.0 / 256.0, 0.5, 0.5);

    float4 out;
    out.r = 1.164 * yuv.r + 1.596 * yuv.b;
    out.g = 1.164 * yuv.r - 0.392 * yuv.g - 0.813 * yuv.b;
    out.b = 1.164 * yuv.r + 2.017 * yuv.g;
    out.rgb *= u.screenDim;
    out.a = 1.0;
    return out;
}
