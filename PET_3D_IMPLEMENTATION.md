# BESTIE Real 3D Pet Renderer V2

Implemented without changing the existing PetProvider/PetService/PetModel/PetScreen state architecture.

## Rendering
- `flutter_3d_controller: ^2.3.0`
- GLB/GLTF assets
- interactive camera/rotation
- animation playback
- model loading/error state

## Architecture
`PetScreen -> PetRoomScene -> PetAvatar3D -> Pet3DAssetCatalog -> GLB`

The old 2D animal and CustomPainter outfit renderer are not used.

## Asset contract
Every outfit is a complete, anatomically fitted GLB. This is deliberate: a separate flat canvas overlay cannot produce the requested realistic clothing fit.

## Current limitation
The renderer is ready, but final production-quality realistic animal/outfit GLBs still have to be supplied. Do not substitute Wikimedia photos or geometric 2D drawings.

For commercial release, each GLB needs a verified redistribution/commercial-use license. A CC0 rigged animal pack such as Gobkit can be used for a technical integration test, but it is explicitly low-poly and is NOT the final realistic BESTIE art direction.
