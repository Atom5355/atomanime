# Anime4K Shaders for ATOM ANIME

This folder should contain the Anime4K shader files for AI upscaling.

## Download Instructions

1. Download the latest Anime4K release from: https://github.com/bloc97/Anime4K/releases
2. Extract the shaders to this folder
3. The following files are required:
   - Anime4K_Clamp_Highlights.glsl
   - Anime4K_Restore_CNN_VL.glsl
   - Anime4K_Upscale_CNN_x2_VL.glsl
   - Anime4K_AutoDownscalePre_x2.glsl
   - Anime4K_AutoDownscalePre_x4.glsl
   - Anime4K_Upscale_CNN_x2_M.glsl

## Performance Notes

- **Mode A (Fast)**: Works well on mid-range GPUs (GTX 1060+)
- **Mode B+B (Quality)**: Recommended for RTX 20 series and above
- **Mode C+A (Ultra)**: Best quality, requires RTX 30/40 series

The app uses Mode A+A by default for balanced quality/performance.
