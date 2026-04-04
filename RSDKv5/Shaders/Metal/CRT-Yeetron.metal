// CRT-Yeetron.metal — scanline + phosphor dot simulation (Yeetron variant).

#define RSDK_PI       3.14159
#define viewSizeHD    720.0
#define intencity     float3(1.1, 0.9, 0.9)

fragment float4 fragment_main(RSDKVarying         in   [[stage_in]],
                              texture2d<float>    tex  [[texture(0)]],
                              sampler             samp [[sampler(0)]],
                              constant RSDKUniforms &u [[buffer(0)]])
{
    float2 viewPos     = floor((u.textureSize / u.pixelSize) * in.texCoord * u.viewSize) + 0.5;
    float  intPos      = fract((viewPos.y * 3.0 + viewPos.x) * 0.166667);

    float4 scanlineCol;
    if (intPos < 0.333)
        scanlineCol.rgb = intencity.xyz;
    else if (intPos < 0.666)
        scanlineCol.rgb = intencity.zxy;
    else
        scanlineCol.rgb = intencity.yzx;

    float2 pixelPos        = in.texCoord * u.textureSize;
    float2 roundedPixelPos = floor(pixelPos);

    scanlineCol.a = clamp(abs(sin(pixelPos.y * RSDK_PI)) + 0.25, 0.5, 1.0);
    pixelPos     -= 0.5;

    float2 invTexPos = -in.texCoord * u.textureSize + (roundedPixelPos + 0.5);

    float2 newTexPos;
    newTexPos.x = clamp(-abs(invTexPos.x * 0.5) + 1.5, 0.8, 1.25);
    newTexPos.y = clamp(-abs(invTexPos.y * 2.0) + 1.25, 0.5, 1.0);

    float2 colorMod;
    colorMod.x = newTexPos.x * newTexPos.y;
    colorMod.y = newTexPos.x * ((scanlineCol.a + newTexPos.y) * 0.5);
    scanlineCol.a *= newTexPos.x;

    float2 texPos = ((pixelPos - clamp(pixelPos, float2(-0.25), float2(0.25)))
                     * 2.0 + roundedPixelPos + 0.5) / u.textureSize;
    float4 texColor = tex.sample(samp, texPos);

    float3 blended;
    blended.r  = scanlineCol.a  * texColor.r;
    blended.gb = colorMod.xy    * texColor.gb;

    float4 out;
    out.rgb = (u.viewSize.y >= viewSizeHD)
              ? (scanlineCol.rgb * blended.rgb)
              : blended.rgb;
    out.rgb *= u.screenDim;
    out.a    = 1.0;
    return out;
}
