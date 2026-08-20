# Rabbisir native assets

## Rabbisir Logo

`Sources/RabbisirCore/Resources/Brand/RabbisirLogo.png` is a creator-supplied brand asset authorized for Rabbisir. The repository copy preserves the supplied PNG bytes without segmentation, redrawing, masks, or derivative animation assets.

- SHA-256: `f04917ae7a975b2b97678429177d2b02c80ccaacfb95141825598f755c1fbf5c`
- Pixel size: 2560×2560 with alpha
- Upstream ownership: none; this is not DeepSeek Harness artwork

`RabbisirLogoTight.png` is an alpha-tight, pixel-identical crop exported from the authorized source through Affinity. `scripts/generate-app-icon-variants.sh` deterministically composites that unchanged alpha mask into two standard macOS icon sets: `AppIconLight.icns` uses a black mark on an off-white `#F2F2EF` tile, and `AppIconDark.icns` uses a white mark on a near-black `#1C1D21` tile. Each variant contains 16, 32, 128, 256, and 512 point resources at 1× and 2× without stretching or upscaling. The running app selects the matching variant from the effective macOS appearance; `AppIcon.icns` remains the light fallback for future bundle metadata.

## About panel identity assets

The About panel packages the creator-authorized, unchanged `YelZapAvatar.png` and the unchanged
official Blurple Discord symbol whose identifying use is permitted by Discord's published Brand
Assets guidance. The DeepSeek upstream link uses a neutral native macOS symbol and non-stylized text;
no DeepSeek logo or organization avatar is packaged. Opening About performs no asset network request.

These marks identify their respective developer, upstream, and community destinations only. They do not imply sponsorship, endorsement, or official partnership with Rabbisir.

The complete rights boundary, creator authorization, source records, immutable digests, trademark
limitations, and DeepSeek brand exclusion are recorded in
[`Legal/BRAND_ASSETS.md`](Legal/BRAND_ASSETS.md). The public bytes are pinned by
[`Legal/ASSET_MANIFEST.sha256`](Legal/ASSET_MANIFEST.sha256).
