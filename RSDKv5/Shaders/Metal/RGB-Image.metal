// RGB-Image.metal — pass-through for pre-decoded RGB images and video frames.

fragment float4 fragment_main(RSDKVarying         in   [[stage_in]],
                              texture2d<float>    tex  [[texture(0)]],
                              sampler             samp [[sampler(0)]],
                              constant RSDKUniforms &u [[buffer(0)]])
{
    float4 color = tex.sample(samp, in.texCoord);
    color.rgb *= u.screenDim;
    return color;
}
