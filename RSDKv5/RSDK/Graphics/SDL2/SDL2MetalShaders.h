#pragma once

// Metal shader support for SDL2RenderDevice on iOS.
// SDL2MetalShaders.mm implements all Metal API calls; this header exposes a
// plain-C interface so SDL2RenderDevice.cpp (compiled as C++) can call in
// without needing Objective-C or Metal headers.

#if TARGET_OS_IPHONE

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// One draw call in a frame: which screen texture (-1 = imageTexture) and
// which vertex-buffer offset (in number of vertices, not bytes).
typedef struct {
    int screenIndex; // 0-3 for game screens, -1 for image/video texture
    int startVert;   // index into the NDC vertex buffer
} MetalDrawCall;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// Call once after SDL_CreateRenderer.  texW/H are the framebuffer texture
// dimensions (512×256 or 1024×512); screenW/H are the logical pixel size.
bool MetalShaders_Init(void *sdlRenderer,
                       float texW, float texH,
                       float screenW, float screenH,
                       int videoTexW, int videoTexH,
                       int isRev02);

// Update the vertex UV extents after a screen resize.
void MetalShaders_UpdateVertexBuffer(float screenW, float screenH,
                                     float texW,    float texH);

// Release all Metal objects.  Call before SDL_DestroyRenderer.
void MetalShaders_Release(void);

// ---------------------------------------------------------------------------
// Shader loading
// ---------------------------------------------------------------------------

// Compile and store one shader.  'source' is the complete Metal source for
// the fragment function; the vertex function is prepended automatically.
// shaderIndex must equal the current shaderCount before the call.
bool MetalShaders_Load(const char *name, bool linear,
                       const char *source, int shaderIndex);

// ---------------------------------------------------------------------------
// Texture uploads  (called every frame from CopyFrameBuffer / SetupVideo*)
// ---------------------------------------------------------------------------

// Upload one game-screen frame buffer (RGB565, row-major, srcPitch columns).
void MetalShaders_UpdateScreenTexture(int screenIdx,
                                      const uint16_t *pixels,
                                      int srcWidth, int srcHeight,
                                      int srcPitch);

// Upload a decoded image (ARGB8888, tightly packed).
void MetalShaders_UpdateImageTexture(int width, int height,
                                     const uint32_t *pixels);

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

// Inject Metal draw calls into the SDL renderer's active command encoder.
// Must be called between SDL_RenderClear and SDL_RenderPresent.
// Handles the dim amount via the screenDim uniform (0.0–1.0).
void MetalShaders_FlipScreen(void           *sdlRenderer,
                             int             shaderID,
                             bool            linear,
                             MetalDrawCall  *draws,
                             int             drawCount,
                             float pixelSizeX,   float pixelSizeY,
                             float textureSizeX, float textureSizeY,
                             float viewSizeX,    float viewSizeY,
                             float screenDim);

#ifdef __cplusplus
}
#endif

#endif // TARGET_OS_IPHONE
