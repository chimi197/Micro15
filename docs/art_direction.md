# Micro 15 art direction

How Micro 15 should look, and the rules every model, material and shader
follows. It comes from Johnny's reference screenshots (a stylized 3D game
with a night camp), used **for style only**. Micro 15 stays a sunny
daytime neighbourhood of blocks of flats in Satu Mare. It keeps its layout,
colours and gameplay.

## What the references do

1. **Light does the drawing.** There are no outlines. Forms read from
   soft light-to-shadow transitions, a warm key light against a cool fill,
   soft contact shadows under and between objects, and value contrast
   between neighbours.
2. **Chunky, simplified geometry with deliberate edges.** Made things
   (chairs, bins, cones) have thick parts, straight lines and small
   chamfers that catch light. Natural things (rocks, logs, canopies) are
   faceted or clumped, with irregular, asymmetric silhouettes. Nothing is
   a bare primitive, and nothing carries tiny detail.
3. **Leafy canopies are built from clusters.** Trees are made of leaf
   clumps with a ragged outline of individual, readable leaves. They are
   lighter on top, darker inside and underneath. Trunks are tall, taper
   and fork.
4. **Muted, value-structured colour.** Large surfaces (ground, walls,
   rocks) are mid-value and slightly desaturated. Saturated colour is
   saved for small things that matter (a cone, a lantern). Each material
   family keeps a narrow colour range.
5. **Restrained surface detail.** Large-scale mottling and a few painted
   marks give ground and big shapes depth. Nothing is photographic,
   glossy, or noisy at gameplay distance.
6. **One degree of exaggeration.** Planks are a bit too thick, legs a bit
   too sturdy, and the same push applies to every asset.

## Rules for Micro 15

### Geometry

| Asset kind | Silhouette | Edges | Shading |
| --- | --- | --- | --- |
| Buildings, balconies, slabs, steps | straight, blocky, clear storey rhythm | hard, flat faces | flat per face |
| Street furniture (benches, bins, fences, lamps, playground) | chunky, slightly thick parts | small chamfers (1–2 cm) on corners that catch light; round tubes stay round | smooth on round parts, flat on boards |
| Trees and bushes | ragged, asymmetric clusters of leaf clumps; tapered, forked trunks | leaf cards, no smooth blobs | normals bent outwards from the canopy (one soft volume) |
| Conifers | stacked, drooping tiers with uneven points | faceted | flat per facet |
| Character | smooth, as modelled | — | smooth |

Triangle budgets: about 2,000 for a tree or bush, 500–1,500 for a street
prop, and buildings as they are. Small details stop drawing with distance
(visibility ranges), so they don't need low-detail versions.

### Light and shading (`game/shaders/soft_light.gdshaderinc`)

- Every shader (`stylized`, `foliage`, `lawn`, `grass`) includes
  `soft_light.gdshaderinc`: Lambert with a small wrap (`light_wrap` 0.2;
  0.45 for foliage, 0.3 for lawns), so the terminator is soft while lit and
  shaded sides keep clear contrast, plus a broad GGX highlight scaled by
  the material's specular. Godot's own `diffuse_lambert_wrap` is not used:
  it wraps by roughness, which on rough materials halves the sun and
  flattens every form.
- Soft sun shadows (high soft-shadow filter, blur 1.5), SSAO for contact
  shadows, ambient light 70% from the sky and 30% a neutral warm grey, so
  shadows read cool without turning blue. There are no cel bands and no
  ink lines; the ink pass stays only as an admin toggle (F2).
- Sun: warm white (1.0, 0.95, 0.86), energy 1.35. `SunCycle` places it
  for the local clock time (default 12:00, about 50° high in the
  south-east, mid-August); towards sunrise and sunset it turns orange and
  dimmer, and the sky horizon and haze warm up; at night a cool blue
  moonlight (energy 0.16) and a dark blue sky take over. Daylight stays
  the game's default.
- Tonemapping is Filmic (exposure 1.0), so bright walls roll off instead of
  clipping. Light haze (fog 0.00025, aerial perspective 0.3) separates
  distant blocks. There is no bloom and no colour grading.

### Materials (`game/scripts/material_library.gd`)

Every glTF material is matched by name to a **family** that sets its
shader, roughness, specular, surface variation and grime. The colour
comes from the palette below, or from the model.

| Family | Roughness | Specular | Variation | Notes |
| --- | --- | --- | --- | --- |
| plaster (walls) | 0.9 | 0.25 | 6% large mottling | darker band near the ground (grime) |
| concrete / slab / kerb / steps | 0.95 | 0.2 | 8% | grime |
| asphalt | 0.95 | 0.15 | 7% plus fine speckle | — |
| paving | 0.9 | 0.2 | 6% | 1 m slab seams |
| painted metal | 0.55 | 0.35 | 3% | fences, bins, containers, lamps |
| bare metal | 0.4 | 0.5 | 2% | tubes, poles |
| wood | 0.8 | 0.2 | 6% | benches |
| glass | 0.08 | 0.6 | 0 | reflects the sky |
| fabric / curtains | 1.0 | 0.1 | 2% | — |
| roof | 0.95 | 0.15 | 8% | — |
| foliage | 0.85 | 0.15 | per-clump shade | double-sided leaf cards |
| skin | 0.65 | 0.3 | 0 | character |
| hair | 0.55 | 0.35 | 0 | character |
| cloth | 0.95 | 0.15 | 0 | character |

### Colour

Large surfaces are muted and mid-to-light in value. Saturated colour goes
on small things only (playground, shop bands, flowers, cones).

- **Blocks of flats:** soft, warm pastels in the range seen around Micro
  15: cream, sand, butter, peach, sage, powder blue, pale lilac. Saturation
  stays at or below 30%, and value is 75–90%. The plinths are a darker,
  warm grey.
- **Ground:** asphalt is a cool, nearly neutral grey (#65686f) around 40%
  value, distinct from the warm light-grey paving (#cfc7b6) and the darker
  kerbs. Lawns are a yellow
  green around 45–50%, with patches.
- **Foliage:** three greens per tree kind (shadow, mid, top), going
  yellower towards the tops. Leaf cards carry a greyscale painted patch of
  hanging leaves (`style/leaf_broad.png` for street trees, poplars and
  bushes, `leaf_small.png` for birches and hedges; repaint with
  `tools/make_leaf_texture.py`), tinted per tree kind in the foliage
  shader and cut out with alpha scissor. Each leaf has a faint darker
  edge and a lighter upper half; the dark core inside each clump is the
  same green, 25% darker. Spruce is a blue green and stays darker than
  the lawn. Birch is a lighter yellow green.
- **Metal:** painted metal uses the Romanian municipal green (#3f6e4a) or
  dark grey. Bare metal is a light grey.
- **Wood:** warm mid brown, lighter on top faces.

### Detail and distance

- Big forms come first: storey bands, balconies and windows carry the
  facades. Fine details (AC units, dishes, pots) stay small and stop
  drawing at 120–200 m.
- Surface variation is large scale (metres). Nothing finer than about
  10 cm per pixel at gameplay distance.
- Repeated assets vary through instance colour (glass, curtains), random
  yaw and scale, and two or three model variants (tree_a/b/c, bush_a/b).

### Making new assets

1. Model in `blender/` as a Python builder (see `build_assets.py`), at real
   scale, with the origin on the ground at the centre, facing −Y.
2. Name materials `C3_<family>_<detail>` (for example `C3_wood`,
   `C3_metal_green`) so `material_library.gd` picks the right family.
3. Give made things thick parts and small chamfers. Give natural things
   clumps and asymmetry.
4. Export to `game/assets/source/`, then run `tools/make_assets.gd`.

### Known gaps

- The blocks of flats are still the flat, hard-edged boxes of the first
  map build; they were recoloured and relit but not remodelled (no
  chamfers on balconies or slabs).
- The palette lives in `material_library.gd`, so the colours in the Blender
  files are the old, more saturated ones until the builders are updated.
- The 3D corner test level (`levels/corner/`) still uses its own older
  `props.glb`; rebuild it with `build_corner_3d.run` to get the new trees.
- Shadow edges under window sills can still show slight stair-stepping
  at some distances.
