// SDL2MetalShaders.mm — see SDL2MetalShaders.h for the public C API.
// Compiled as Objective-C++ (.mm). All engine-specific macros are passed in
// as parameters so this file has zero dependencies on engine headers.

#if TARGET_OS_IPHONE

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <SDL.h>

#include "SDL2MetalShaders.h"

// ---------------------------------------------------------------------------
// Vertex struct — must match RenderVertex: float3 pos, uint32 color, float2 tex
// ---------------------------------------------------------------------------
struct MetalVertex { float pos[3]; uint32_t color; float tex[2]; };
// sizeof(MetalVertex) == 24

// ---------------------------------------------------------------------------
// 60-entry NDC table covering Rev02 (60) and Rev01 (24 used).
// UV slots that are 1.0 get patched at runtime to the correct texel fraction.
// ---------------------------------------------------------------------------
static const MetalVertex kBaseVerts[60] = {
    // 1 Screen (0-5)
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{+1,+1,1},0xFFFFFFFF,{1,0}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{−1,−1,1},0xFFFFFFFF,{0,1}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
    // 2P Bordered top (6-11)
    {{+.5f,0,1},0xFFFFFFFF,{1,1}},{{+.5f,+1,1},0xFFFFFFFF,{1,0}},{{−.5f,+1,1},0xFFFFFFFF,{0,0}},
    {{+.5f,0,1},0xFFFFFFFF,{1,1}},{{−.5f,0,1},0xFFFFFFFF,{0,1}},{{−.5f,+1,1},0xFFFFFFFF,{0,0}},
    // 2P Bordered bottom (12-17)
    {{+.5f,−1,1},0xFFFFFFFF,{1,1}},{{+.5f,0,1},0xFFFFFFFF,{1,0}},{{−.5f,0,1},0xFFFFFFFF,{0,0}},
    {{+.5f,−1,1},0xFFFFFFFF,{1,1}},{{−.5f,−1,1},0xFFFFFFFF,{0,1}},{{−.5f,0,1},0xFFFFFFFF,{0,0}},
    // 2P Stretched top (18-23)
    {{+1,0,1},0xFFFFFFFF,{1,1}},{{+1,+1,1},0xFFFFFFFF,{1,0}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
    {{+1,0,1},0xFFFFFFFF,{1,1}},{{−1,0,1},0xFFFFFFFF,{0,1}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
    // 2P Stretched bottom (24-29)
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{+1,0,1},0xFFFFFFFF,{1,0}},{{−1,0,1},0xFFFFFFFF,{0,0}},
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{−1,−1,1},0xFFFFFFFF,{0,1}},{{−1,0,1},0xFFFFFFFF,{0,0}},
    // 4P top-left (30-35)
    {{0,0,1},0xFFFFFFFF,{1,1}},{{0,+1,1},0xFFFFFFFF,{1,0}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
    {{0,0,1},0xFFFFFFFF,{1,1}},{{−1,0,1},0xFFFFFFFF,{0,1}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
    // 4P top-right (36-41)
    {{+1,0,1},0xFFFFFFFF,{1,1}},{{+1,+1,1},0xFFFFFFFF,{1,0}},{{0,+1,1},0xFFFFFFFF,{0,0}},
    {{+1,0,1},0xFFFFFFFF,{1,1}},{{0,0,1},0xFFFFFFFF,{0,1}},{{0,+1,1},0xFFFFFFFF,{0,0}},
    // 4P bottom-right (42-47)
    {{0,−1,1},0xFFFFFFFF,{1,1}},{{0,0,1},0xFFFFFFFF,{1,0}},{{−1,0,1},0xFFFFFFFF,{0,0}},
    {{0,−1,1},0xFFFFFFFF,{1,1}},{{−1,−1,1},0xFFFFFFFF,{0,1}},{{−1,0,1},0xFFFFFFFF,{0,0}},
    // 4P bottom-left (48-53)
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{+1,0,1},0xFFFFFFFF,{1,0}},{{0,0,1},0xFFFFFFFF,{0,0}},
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{0,−1,1},0xFFFFFFFF,{0,1}},{{0,0,1},0xFFFFFFFF,{0,0}},
    // Image/Video fullscreen (54-59)
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{+1,+1,1},0xFFFFFFFF,{1,0}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
    {{+1,−1,1},0xFFFFFFFF,{1,1}},{{−1,−1,1},0xFFFFFFFF,{0,1}},{{−1,+1,1},0xFFFFFFFF,{0,0}},
};

struct ShaderUniforms { float pixelSize[2], textureSize[2], viewSize[2], screenDim, _pad; };

static id<MTLDevice>              s_device         = nil;
static id<MTLBuffer>              s_vertexBuf      = nil;
static id<MTLTexture>             s_screenTex[4]   = {};
static id<MTLTexture>             s_imageTex       = nil;
static id<MTLSamplerState>        s_samplerNearest = nil;
static id<MTLSamplerState>        s_samplerLinear  = nil;
static MTLVertexDescriptor       *s_vertexDesc     = nil;
#define MAX_SH 16
static id<MTLRenderPipelineState> s_pipelines[MAX_SH];
static int                        s_shaderCount    = 0;
static int                        s_vertexCount    = 24;

static uint32_t s_expandBuf[1024 * 512];

static const char *kHeader =
    "#include <metal_stdlib>\nusing namespace metal;\n"
    "struct RSDKVertex  { float3 position [[attribute(0)]]; float2 texCoord [[attribute(1)]]; };\n"
    "struct RSDKVarying { float4 position [[position]]; float2 texCoord; };\n"
    "struct RSDKUniforms{ float2 pixelSize; float2 textureSize; float2 viewSize; float screenDim; };\n"
    "vertex RSDKVarying vertex_main(RSDKVertex in [[stage_in]]) {\n"
    "    RSDKVarying o; o.position=float4(in.position,1.0); o.texCoord=in.texCoord; return o; }\n";

static void PatchUVs(MetalVertex *v, int count, float uMax, float vMax) {
    int game = count - 6;
    for (int i = 0; i < game; ++i) {
        if (v[i].tex[0]) v[i].tex[0] = uMax;
        if (v[i].tex[1]) v[i].tex[1] = vMax;
    }
}

bool MetalShaders_Init(void *sdlRenderer,
                       float texW, float texH,
                       float screenW, float screenH,
                       int videoTexW, int videoTexH,
                       int isRev02)
{
    s_vertexCount = isRev02 ? 60 : 24;

    CAMetalLayer *layer = (__bridge CAMetalLayer *)
        SDL_RenderGetMetalLayer((SDL_Renderer *)sdlRenderer);
    if (!layer) return false;
    s_device = layer.device;

    s_vertexDesc = [[MTLVertexDescriptor alloc] init];
    s_vertexDesc.attributes[0].format = MTLVertexFormatFloat3; s_vertexDesc.attributes[0].offset = 0;  s_vertexDesc.attributes[0].bufferIndex = 0;
    s_vertexDesc.attributes[1].format = MTLVertexFormatFloat2; s_vertexDesc.attributes[1].offset = 16; s_vertexDesc.attributes[1].bufferIndex = 0;
    s_vertexDesc.layouts[0].stride = sizeof(MetalVertex);

    MetalVertex verts[60];
    memcpy(verts, kBaseVerts, sizeof(verts));
    PatchUVs(verts, s_vertexCount, screenW / texW, screenH / texH);
    s_vertexBuf = [s_device newBufferWithBytes:verts length:sizeof(verts) options:MTLResourceStorageModeShared];
    if (!s_vertexBuf) return false;

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:(NSUInteger)texW height:(NSUInteger)texH mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead; td.storageMode = MTLStorageModeShared;
    for (int i = 0; i < 4; ++i) s_screenTex[i] = [s_device newTextureWithDescriptor:td];

    MTLTextureDescriptor *imgd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:(NSUInteger)(videoTexW > 0 ? videoTexW : 1024) height:(NSUInteger)(videoTexH > 0 ? videoTexH : 512) mipmapped:NO];
    imgd.usage = MTLTextureUsageShaderRead; imgd.storageMode = MTLStorageModeShared;
    s_imageTex = [s_device newTextureWithDescriptor:imgd];
    if (!s_imageTex) return false;

    MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
    sd.sAddressMode = sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterNearest;
    s_samplerNearest = [s_device newSamplerStateWithDescriptor:sd];
    sd.minFilter = sd.magFilter = MTLSamplerMinMagFilterLinear;
    s_samplerLinear = [s_device newSamplerStateWithDescriptor:sd];

    s_shaderCount = 0;
    return true;
}

void MetalShaders_UpdateVertexBuffer(float screenW, float screenH, float texW, float texH) {
    if (!s_vertexBuf) return;
    MetalVertex *v = (MetalVertex *)s_vertexBuf.contents;
    memcpy(v, kBaseVerts, sizeof(MetalVertex) * 60);
    PatchUVs(v, s_vertexCount, screenW / texW, screenH / texH);
}

void MetalShaders_Release(void) {
    for (int i = 0; i < MAX_SH; ++i) s_pipelines[i] = nil;
    for (int i = 0; i < 4;      ++i) s_screenTex[i]  = nil;
    s_imageTex = s_vertexBuf = nil;
    s_samplerNearest = s_samplerLinear = nil;
    s_vertexDesc = nil; s_device = nil; s_shaderCount = 0;
}

bool MetalShaders_Load(const char *name, bool linear, const char *source, int idx) {
    if (idx >= MAX_SH || !s_device) return false;
    NSString *src = [NSString stringWithFormat:@"%s%s", kHeader, source];
    NSError *err = nil;
    id<MTLLibrary> lib = [s_device newLibraryWithSource:src options:nil error:&err];
    if (!lib) { NSLog(@"[Metal] '%s': %@", name, err); return false; }
    id<MTLFunction> vf = [lib newFunctionWithName:@"vertex_main"];
    id<MTLFunction> ff = [lib newFunctionWithName:@"fragment_main"];
    if (!vf || !ff) { NSLog(@"[Metal] '%s': missing function", name); return false; }
    MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction = vf; pd.fragmentFunction = ff; pd.vertexDescriptor = s_vertexDesc;
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    s_pipelines[idx] = [s_device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!s_pipelines[idx]) { NSLog(@"[Metal] '%s' link: %@", name, err); return false; }
    s_shaderCount = idx + 1;
    return true;
}

void MetalShaders_UpdateScreenTexture(int idx, const uint16_t *pixels, int w, int h, int pitch) {
    if (idx < 0 || idx >= 4 || !s_screenTex[idx]) return;
    for (int y = 0; y < h; ++y) {
        const uint16_t *src = pixels + y * pitch;
        uint32_t       *dst = s_expandBuf + y * w;
        for (int x = 0; x < w; ++x) {
            uint16_t p = src[x];
            uint32_t r = (p>>11)&0x1F; r=(r<<3)|(r>>2);
            uint32_t g = (p>> 5)&0x3F; g=(g<<2)|(g>>4);
            uint32_t b = (p    )&0x1F; b=(b<<3)|(b>>2);
            dst[x] = 0xFF000000u|(r<<16)|(g<<8)|b;
        }
    }
    [s_screenTex[idx] replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0
                          withBytes:s_expandBuf bytesPerRow:(NSUInteger)(w*4)];
}

void MetalShaders_UpdateImageTexture(int w, int h, const uint32_t *pixels) {
    if (!s_imageTex) return;
    [s_imageTex replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0
                    withBytes:pixels bytesPerRow:(NSUInteger)(w*4)];
}

void MetalShaders_FlipScreen(void *sdlRenderer, int shaderID, bool linear,
                             MetalDrawCall *draws, int drawCount,
                             float psx, float psy, float tsx, float tsy,
                             float vsx, float vsy, float dim)
{
    if (shaderID < 0 || shaderID >= s_shaderCount || !s_pipelines[shaderID]) return;
    id<MTLRenderCommandEncoder> enc = (__bridge id<MTLRenderCommandEncoder>)
        SDL_RenderGetMetalCommandEncoder((SDL_Renderer *)sdlRenderer);
    if (!enc) return;
    [enc setRenderPipelineState:s_pipelines[shaderID]];
    [enc setVertexBuffer:s_vertexBuf offset:0 atIndex:0];
    [enc setFragmentSamplerState:(linear ? s_samplerLinear : s_samplerNearest) atIndex:0];
    ShaderUniforms u = {{psx,psy},{tsx,tsy},{vsx,vsy},dim,0};
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    for (int i = 0; i < drawCount; ++i) {
        id<MTLTexture> tex = draws[i].screenIndex < 0 ? s_imageTex : s_screenTex[draws[i].screenIndex];
        if (!tex) continue;
        [enc setFragmentTexture:tex atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:(NSUInteger)draws[i].startVert vertexCount:6];
    }
}

#endif // TARGET_OS_IPHONE
