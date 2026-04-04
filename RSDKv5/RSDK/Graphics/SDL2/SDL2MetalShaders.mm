// SDL2MetalShaders.mm
// Compiled as Objective-C++ (.mm).  Provides Metal shader management for the
// SDL2 render device on iOS by injecting draws into SDL's Metal command encoder.

#if TARGET_OS_IPHONE

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <SDL.h>

#include "SDL2MetalShaders.h"

// ---------------------------------------------------------------------------
// Vertex layout (must match engine's RenderVertex exactly)
//   offset  0 : float3 pos    (12 bytes)
//   offset 12 : uint32 color  ( 4 bytes, always 0xFFFFFFFF – ignored)
//   offset 16 : float2 tex    ( 8 bytes)
//   stride  24 bytes
// ---------------------------------------------------------------------------

struct MetalVertex {
    float    pos[3];
    uint32_t color;
    float    tex[2];
};

// Runtime vertex count — set by MetalShaders_Init from the isRev02 flag.
static int s_vertexCount = 24;

// NDC vertex buffer — 60 entries covers both Rev01 (24 used) and Rev02 (60 used).
// UV.x/y == 0 or 1 are placeholders replaced by MetalShaders_UpdateVertexBuffer.
static MetalVertex s_baseVerts[60] = {
    // 1 Screen (0)
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 2P Bordered – top (6)
    { { +0.5f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +0.5f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -0.5f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +0.5f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -0.5f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -0.5f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 2P Bordered – bottom (12)
    { { +0.5f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +0.5f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -0.5f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +0.5f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -0.5f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -0.5f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 2P Stretched – top (18)
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 2P Stretched – bottom (24)
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 4P top-left (30)
    { {  0.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { {  0.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { {  0.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 4P top-right (36)
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { {  0.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { {  0.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { {  0.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 4P bottom-right (42)
    { {  0.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { {  0.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { {  0.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 4P bottom-left (48)
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { {  0.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { {  0.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { {  0.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // Image/Video fullscreen (54)
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
};
// 60-entry table — runtime s_vertexCount selects 24 or 60.
// The 24-entry (non-Rev02) verts below fill indices 0-23; they are
// identical in layout so we embed them as a second initialiser block
// that is never actually used at runtime — we rely on s_vertexCount.
// Remove the duplicate block:
#if 0 // non-Rev02 block (replaced by s_vertexCount runtime flag)
static MetalVertex s_baseVerts[24] = {
    // 1 Screen (0)
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 2P Stretched – top (6)
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // 2P Stretched – bottom (12)
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f,  0.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f,  0.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },

    // Image/Video fullscreen (18)
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { +1.f, +1.f, 1.f }, 0xFFFFFFFF, { 1.f, 0.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
    { { +1.f, -1.f, 1.f }, 0xFFFFFFFF, { 1.f, 1.f } },
    { { -1.f, -1.f, 1.f }, 0xFFFFFFFF, { 0.f, 1.f } },
    { { -1.f, +1.f, 1.f }, 0xFFFFFFFF, { 0.f, 0.f } },
};
#endif // end non-Rev02 block

// ---------------------------------------------------------------------------
// Uniform block (matches the layout expected by every fragment shader)
// ---------------------------------------------------------------------------
struct ShaderUniforms {
    float pixelSize[2];
    float textureSize[2];
    float viewSize[2];
    float screenDim;
    float _pad; // keep 16-byte aligned
};

// ---------------------------------------------------------------------------
// Module-level state
// ---------------------------------------------------------------------------
static id<MTLDevice>              s_device          = nil;
static id<MTLBuffer>              s_vertexBuf       = nil;
static id<MTLTexture>             s_screenTex[4]    = {};
static id<MTLTexture>             s_imageTex        = nil;
static id<MTLSamplerState>        s_samplerNearest  = nil;
static id<MTLSamplerState>        s_samplerLinear   = nil;

static MTLVertexDescriptor       *s_vertexDesc      = nil;

#define MAX_SHADERS 16
static id<MTLRenderPipelineState> s_pipelines[MAX_SHADERS] = {};
static bool                       s_pipelineLinear[MAX_SHADERS] = {};
static int                        s_shaderCount     = 0;

// Scratch buffer for RGB565 → BGRA8 expansion (max 1024×512)
static uint32_t s_expandBuf[1024 * 512];

// ---------------------------------------------------------------------------
// Common Metal shader source prepended to every fragment source
// ---------------------------------------------------------------------------
static const char *kShaderHeader =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "\n"
    "struct RSDKVertex {\n"
    "    float3 position [[attribute(0)]];\n"
    "    float2 texCoord [[attribute(1)]];\n"
    "};\n"
    "struct RSDKVarying {\n"
    "    float4 position [[position]];\n"
    "    float2 texCoord;\n"
    "};\n"
    "struct RSDKUniforms {\n"
    "    float2 pixelSize;\n"
    "    float2 textureSize;\n"
    "    float2 viewSize;\n"
    "    float  screenDim;\n"
    "};\n"
    "\n"
    "vertex RSDKVarying vertex_main(RSDKVertex in [[stage_in]]) {\n"
    "    RSDKVarying out;\n"
    "    out.position = float4(in.position, 1.0);\n"
    "    out.texCoord = in.texCoord;\n"
    "    return out;\n"
    "}\n"
    "\n";

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

static id<MTLRenderPipelineState> CompilePipeline(const char *name,
                                                  const char *fragSource,
                                                  MTLPixelFormat pixFmt,
                                                  NSError **outError)
{
    // Concatenate header + fragment source
    NSString *fullSrc = [NSString stringWithFormat:@"%s%s", kShaderHeader, fragSource];

    id<MTLLibrary> lib = [s_device newLibraryWithSource:fullSrc options:nil error:outError];
    if (!lib) return nil;

    id<MTLFunction> vertFn = [lib newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragFn = [lib newFunctionWithName:@"fragment_main"];

    if (!vertFn || !fragFn) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"MetalShaders"
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey:
                                           [NSString stringWithFormat:
                                               @"Missing vertex_main or fragment_main in shader '%s'", name]}];
        }
        return nil;
    }

    MTLRenderPipelineDescriptor *pDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pDesc.vertexFunction   = vertFn;
    pDesc.fragmentFunction = fragFn;
    pDesc.vertexDescriptor = s_vertexDesc;
    pDesc.colorAttachments[0].pixelFormat = pixFmt;

    return [s_device newRenderPipelineStateWithDescriptor:pDesc error:outError];
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

bool MetalShaders_Init(void *sdlRenderer,
                       float texW, float texH,
                       float screenW, float screenH,
                       int videoTexW, int videoTexH,
                       int isRev02)
{
    // Set runtime vertex count from isRev02 flag
    s_vertexCount = isRev02 ? 60 : 24;

    // Grab the Metal device from SDL's renderer
    CAMetalLayer *layer = (__bridge CAMetalLayer *)SDL_RenderGetMetalLayer((SDL_Renderer *)sdlRenderer);
    if (!layer) return false;

    s_device = layer.device;

    // ── Vertex descriptor ────────────────────────────────────────────────────
    s_vertexDesc = [[MTLVertexDescriptor alloc] init];
    // attribute 0: float3 position at byte offset 0
    s_vertexDesc.attributes[0].format      = MTLVertexFormatFloat3;
    s_vertexDesc.attributes[0].offset      = 0;
    s_vertexDesc.attributes[0].bufferIndex = 0;
    // attribute 1: float2 texCoord at byte offset 16 (past the 4-byte color)
    s_vertexDesc.attributes[1].format      = MTLVertexFormatFloat2;
    s_vertexDesc.attributes[1].offset      = 16;
    s_vertexDesc.attributes[1].bufferIndex = 0;
    s_vertexDesc.layouts[0].stride         = sizeof(MetalVertex);

    // ── Vertex buffer (contents updated by UpdateVertexBuffer) ───────────────
    MetalVertex verts[60]; // fixed max; s_vertexCount selects how many are used
    memcpy(verts, s_baseVerts, sizeof(verts));

    float uMax = screenW / texW;
    float vMax = screenH / texH;
    // Patch UV in the non-image-quad vertices
    int gameVerts = s_vertexCount - 6;
    for (int i = 0; i < gameVerts; ++i) {
        if (verts[i].tex[0] != 0.f) verts[i].tex[0] = uMax;
        if (verts[i].tex[1] != 0.f) verts[i].tex[1] = vMax;
    }
    // Image quad stays at 1,1 (full texture)

    s_vertexBuf = [s_device newBufferWithBytes:verts
                                        length:sizeof(verts)
                                       options:MTLResourceStorageModeShared];

    // ── Screen textures (BGRA8, one per screen slot) ─────────────────────────
    MTLTextureDescriptor *scrDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                          width:(NSUInteger)texW
                                                         height:(NSUInteger)texH
                                                      mipmapped:NO];
    scrDesc.usage       = MTLTextureUsageShaderRead;
    scrDesc.storageMode = MTLStorageModeShared;

    for (int i = 0; i < 4; ++i)
        s_screenTex[i] = [s_device newTextureWithDescriptor:scrDesc];

    // ── Image/video texture (BGRA8) ──────────────────────────────────────────
    MTLTextureDescriptor *imgDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                          width:(NSUInteger)videoTexW
                                                         height:(NSUInteger)videoTexH
                                                      mipmapped:NO];
    imgDesc.usage       = MTLTextureUsageShaderRead;
    imgDesc.storageMode = MTLStorageModeShared;
    s_imageTex = [s_device newTextureWithDescriptor:imgDesc];

    // ── Samplers ─────────────────────────────────────────────────────────────
    MTLSamplerDescriptor *sDesc = [[MTLSamplerDescriptor alloc] init];

    sDesc.minFilter = MTLSamplerMinMagFilterNearest;
    sDesc.magFilter = MTLSamplerMinMagFilterNearest;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    s_samplerNearest = [s_device newSamplerStateWithDescriptor:sDesc];

    sDesc.minFilter = MTLSamplerMinMagFilterLinear;
    sDesc.magFilter = MTLSamplerMinMagFilterLinear;
    s_samplerLinear = [s_device newSamplerStateWithDescriptor:sDesc];

    s_shaderCount = 0;
    return true;
}

void MetalShaders_UpdateVertexBuffer(float screenW, float screenH,
                                     float texW,    float texH)
{
    if (!s_vertexBuf) return;

    MetalVertex *verts = (MetalVertex *)s_vertexBuf.contents;
    float uMax = screenW / texW;
    float vMax = screenH / texH;

    memcpy(verts, s_baseVerts, sizeof(MetalVertex) * s_vertexCount);

    int gameVerts = s_vertexCount - 6;
    for (int i = 0; i < gameVerts; ++i) {
        if (verts[i].tex[0] != 0.f) verts[i].tex[0] = uMax;
        if (verts[i].tex[1] != 0.f) verts[i].tex[1] = vMax;
    }
}

void MetalShaders_Release(void)
{
    for (int i = 0; i < MAX_SHADERS; ++i) s_pipelines[i] = nil;
    for (int i = 0; i < 4; ++i)           s_screenTex[i]  = nil;
    s_imageTex       = nil;
    s_vertexBuf      = nil;
    s_samplerNearest = nil;
    s_samplerLinear  = nil;
    s_vertexDesc     = nil;
    s_device         = nil;
    s_shaderCount    = 0;
}

bool MetalShaders_Load(const char *name, bool linear,
                       const char *source, int shaderIndex)
{
    if (shaderIndex >= MAX_SHADERS || !s_device) return false;

    // Determine pixel format from the SDL renderer's drawable
    // SDL_RenderGetMetalLayer gives us the CAMetalLayer which has pixelFormat
    // but we don't have the renderer here. BGRA8Unorm is the universal safe choice.
    MTLPixelFormat fmt = MTLPixelFormatBGRA8Unorm;

    NSError *err = nil;
    id<MTLRenderPipelineState> pipeline = CompilePipeline(name, source, fmt, &err);
    if (!pipeline) {
        NSLog(@"[MetalShaders] Failed to compile '%s': %@", name, err.localizedDescription);
        return false;
    }

    s_pipelines[shaderIndex]    = pipeline;
    s_pipelineLinear[shaderIndex] = linear;
    s_shaderCount = shaderIndex + 1;
    return true;
}

// ---------------------------------------------------------------------------
// Texture uploads
// ---------------------------------------------------------------------------

void MetalShaders_UpdateScreenTexture(int screenIdx,
                                      const uint16_t *pixels,
                                      int srcWidth, int srcHeight,
                                      int srcPitch)
{
    if (!s_screenTex[screenIdx]) return;

    // Expand RGB565 → BGRA8
    // RGB565: R=bits[15:11], G=bits[10:5], B=bits[4:0]
    // BGRA8Unorm in little-endian uint32: byte0=B, byte1=G, byte2=R, byte3=A
    //   → uint32 = (A<<24)|(R<<16)|(G<<8)|B
    for (int y = 0; y < srcHeight; ++y) {
        const uint16_t *src = pixels + y * srcPitch;
        uint32_t       *dst = s_expandBuf + y * srcWidth;
        for (int x = 0; x < srcWidth; ++x) {
            uint16_t px = src[x];
            uint32_t r  = (px >> 11) & 0x1F; r = (r << 3) | (r >> 2);
            uint32_t g  = (px >>  5) & 0x3F; g = (g << 2) | (g >> 4);
            uint32_t b  = (px      ) & 0x1F; b = (b << 3) | (b >> 2);
            dst[x] = 0xFF000000u | (r << 16) | (g << 8) | b;
        }
    }

    [s_screenTex[screenIdx] replaceRegion:MTLRegionMake2D(0, 0, srcWidth, srcHeight)
                              mipmapLevel:0
                                withBytes:s_expandBuf
                              bytesPerRow:(NSUInteger)(srcWidth * 4)];
}

void MetalShaders_UpdateImageTexture(int width, int height,
                                     const uint32_t *pixels)
{
    // Incoming format is ARGB8888; Metal BGRA8Unorm wants BGRA in memory.
    // ARGB in a uint32 (little-endian): byte0=B, byte1=G, byte2=R, byte3=A — actually:
    // SDL uses ARGB8888 meaning the uint32 value is 0xAARRGGBB.
    // In memory (little-endian): byte0=BB, byte1=GG, byte2=RR, byte3=AA.
    // MTLPixelFormatBGRA8Unorm reads: byte0=B, byte1=G, byte2=R, byte3=A.
    // These match — so we can upload directly with no swizzle.
    if (!s_imageTex) return;
    [s_imageTex replaceRegion:MTLRegionMake2D(0, 0, width, height)
                  mipmapLevel:0
                    withBytes:pixels
                  bytesPerRow:(NSUInteger)(width * 4)];
}

// ---------------------------------------------------------------------------
// Frame rendering
// ---------------------------------------------------------------------------

void MetalShaders_FlipScreen(void           *sdlRenderer,
                             int             shaderID,
                             bool            linear,
                             MetalDrawCall  *draws,
                             int             drawCount,
                             float pixelSizeX,   float pixelSizeY,
                             float textureSizeX, float textureSizeY,
                             float viewSizeX,    float viewSizeY,
                             float screenDim)
{
    if (shaderID < 0 || shaderID >= s_shaderCount) return;
    if (!s_pipelines[shaderID]) return;

    // Get the command encoder SDL is currently using for this frame
    id<MTLRenderCommandEncoder> enc =
        (__bridge id<MTLRenderCommandEncoder>)
        SDL_RenderGetMetalCommandEncoder((SDL_Renderer *)sdlRenderer);
    if (!enc) return;

    [enc setRenderPipelineState:s_pipelines[shaderID]];
    [enc setVertexBuffer:s_vertexBuf offset:0 atIndex:0];

    id<MTLSamplerState> sampler = linear ? s_samplerLinear : s_samplerNearest;

    ShaderUniforms uniforms;
    uniforms.pixelSize[0]   = pixelSizeX;
    uniforms.pixelSize[1]   = pixelSizeY;
    uniforms.textureSize[0] = textureSizeX;
    uniforms.textureSize[1] = textureSizeY;
    uniforms.viewSize[0]    = viewSizeX;
    uniforms.viewSize[1]    = viewSizeY;
    uniforms.screenDim      = screenDim;
    uniforms._pad           = 0.f;

    [enc setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [enc setFragmentSamplerState:sampler atIndex:0];

    for (int i = 0; i < drawCount; ++i) {
        id<MTLTexture> tex = (draws[i].screenIndex < 0)
                             ? s_imageTex
                             : s_screenTex[draws[i].screenIndex];
        if (!tex) continue;

        [enc setFragmentTexture:tex atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:(NSUInteger)draws[i].startVert
                vertexCount:6];
    }

    // Do NOT call [enc endEncoding] — SDL_RenderPresent owns the encoder lifetime.
}

#endif // TARGET_OS_IPHONE
