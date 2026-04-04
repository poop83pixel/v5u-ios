// YUV-420.metal — YCbCr 4:2:0 decode.
// Y is stored in the red channel at full resolution; U/V are packed into
// green/blue in the bottom-left quadrant (same packing as the CPU side).

fragment float4 fragment_main(RSDKVarying         in   [[stage_in]],
                              texture2d<float>    tex  [[texture(0)]],
                              sampler             samp [[sampler(0)]],
                              constant RSDKUniforms &u [[buffer(0)]])
{
    float3 yuv;
    yuv.r  = tex.sample(samp, in.texCoord).r;
    yuv.gb = tex.sample(samp, clamp(in.texCoord / 2.0, 0.0, 0.499)).gb;
    yuv   -= float3(16.0 / 256.0, 0.5, 0.5);

    float4 out;
    out.r = 1.164 * yuv.r + 1.596 * yuv.b;
    out.g = 1.164 * yuv.r - 0.392 * yuv.g - 0.813 * yuv.b;
    out.b = 1.164 * yuv.r + 2.017 * yuv.g;
    out.rgb *= u.screenDim;
    out.a = 1.0;
    return out;
}
