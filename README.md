# Micro 15

A third-person exploration game (single player and co-op) set in a cartoon
version of Micro 15, the neighbourhood in Satu Mare, Romania. Mini-games may
use other camera styles later.

![The whole of Micro 15 in the game](docs/renders/map_south.png)

## Art direction

Flat "vector" look with bold dark outlines and saturated colours, in the
spirit of [the style reference](docs/style_reference.png): cel shading with
three hard light bands, no textures, inverted-hull outlines.

## Playing (`game/`, Godot 4.7)

Open `game/` in Godot 4.7 and press F5. WASD to move, mouse to look, Shift to
run, Space to jump, Esc frees the mouse. Running with `-- --shots` saves
preview renders to `docs/renders/` and quits; `-- --selftest` walks, runs and
jumps the player on its own and prints which animation played when.

## Playable character (`game/characters/kid/`)

![The boy in the game](docs/renders/kid_face.png)

The boy from [the character sheet](docs/character_sheet.png), about 1.5 m
tall, built by `blender/build_character.py` in layers, like a character with
an outfit system:

- **Base body**: one smooth, watertight mesh (Skin modifier + subdivision)
  skinned to a 26-bone rig (root, hips, 3-bone spine, neck, head, shoulders,
  arms, hands, fingers, thighs, shins, feet, toes and three hair bones) with
  automatic weights. It is exported in pieces (`body_torso_upper`,
  `body_pelvis`, `body_upper_arms`, `body_thighs`, `body_ankles`,
  `body_feet`... and `body_base`) whose seams match exactly.
- **Head, face, hair, hands**: smooth separate meshes; spiky hair made of a
  cap plus ~120 pointed locks weighted to the hair bones.
- **Garments** (`garment_shirt`, `garment_shorts`, `garment_socks`,
  `garment_shoes`): separate meshes, each modelled from its own stick figure,
  cut open at the hems, given thickness and rolled edges, fitted to stay
  clear of the body and of the garments underneath, and skinned with weights
  taken from the body surface under them.

`kid.json` lists the garments, the body pieces each one hides, the default
outfit, the spring (hair) bones and the gait speeds. In the game
`player.wear([...])` shows a set of garments and hides the body pieces they
cover, so no skin can poke through clothes and new outfits or accessories
can be added later without touching the body.

Animations are procedural: `walk` and `run` plant the feet with two-bone IK
(heel strike, roll, toe-off) with pelvis bob, sway and twist, a
counter-rotating spine, arm swing with follow-through and a steady head;
`jump`, `fall` and `land` (with a squash), and a breathing, weight-shifting
`idle`.

`game/scripts/player.gd` plays them: walk and run sped up to match the
ground speed (feet don't slide) and switched at the same point of the stride,
leaning into turns and speed changes, hair bouncing on
`SpringBoneSimulator3D`, jump on take-off, fall after a short time in the air
and a landing crouch. The character only gets ink on its outer edges
(materials named `CH_*` write ink mode 0.5, see `ink_outline.gdshader`).

```python
import sys; sys.path.insert(0, r"<repo>/blender")
import build_character; build_character.run(r"<repo>")
build_character.preview(r"<repo>")      # optional: turnaround renders in renders/kid/
```

## The whole map (`game/levels/micro15/`)

![Street level](docs/renders/map_street.png)

The main scene, `levels/micro15/micro15.tscn`, is the whole neighbourhood
(about 1.24 km × 1.17 km) in full 3D, built by `blender/build_map.py` from
the OpenStreetMap extract with the same modelling rules as the corner below:
343 buildings (blocks of flats, P+10 towers, houses, garages, schools, the
hospital, churches with towers and onion domes, shops with shop fronts), all
roads with raised sidewalks, about 2,400 trees and poplars, 500 bushes, 545 lamps
and 157 benches.

* Buildings are exported as light shells (`buildings.glb`). Their ~140,000
  repeated details (windows, balcony doors, open and enclosed balconies,
  entrances, curtains, AC units, dishes, pots, drainpipes, roof huts,
  antennas, vents, garage doors, shop fronts) are modelled once in
  `details.glb` and placed from `details.json`. Godot draws each type with a
  MultiMesh per 96 m cell, and small details stop drawing beyond 120–450 m.
* Trees and street furniture work the same way (`props.glb`, `props.json`).
* 3D grass is built in chunks around the camera as you walk and freed behind
  you (`scripts/grass_field.gd`, mask from `tools/make_grass_mask.py`).
* Buildings, kerbs, tree trunks and lamp posts are solid; invisible walls
  keep the player inside the mapped area. The map loads in under a second.

Rebuild it from Blender's Python console, then regenerate the grass mask:

```python
import sys; sys.path.insert(0, r"<repo>/blender")
import build_map; build_map.run(r"<repo>")      # or part="buildings" / "ground" / "details" / "props"
```

```
python tools/make_grass_mask.py
```

`props` reads the tree, bush, lamp and bench positions from
`blender/micro15_world.blend`, so run it with that file open.

## 3D corner test (`game/levels/corner/`)

![Street in the 3D corner](docs/renders/corner_street.png)

A walkable, fully 3D corner of Micro 15 (around Aleea Constelației and
Aleea Proiectantului) that sets the look for the whole map:

* `blender/build_corner_3d.py` models every block from its OSM footprint:
  recessed windows with frames, sills and curtains, open and enclosed
  balconies (some with flower pots or satellite dishes), stairwell entrances
  with canopies and steps, landing windows, plinths with basement vents,
  drainpipes, AC units, roof parapets, roof stair houses and antennas. Roads
  have raised sidewalks and kerbs. It also models stylised 3D trees,
  poplars, bushes, lamps and benches. Output: `game/levels/corner/*.glb`
  and `props.json`.
* `tools/make_grass_mask.py corner` marks where grass grows (`grass_mask.png`).
* `game/scripts/grass_field.gd` scatters real 3D grass blades and small
  flowers on the lawns (MultiMesh chunks, drawn up to 75 m from the camera,
  swaying in the wind).
* Shaders in `game/shaders/`: `toon` (three hard light bands),
  `foliage` (round shading on tree canopies, sway), `grass`, `lawn`, and
  `ink_outline` (ink lines on silhouettes and creases, fading with distance).
* `game/levels/corner/corner.tscn` is the corner on its own (open it and
  press F6).

Rebuild the corner from Blender's Python console:

```python
import sys; sys.path.insert(0, r"<repo>/blender")
import build_corner_3d; build_corner_3d.run(r"<repo>")
```

## World (`blender/`)

| File | What it is |
| --- | --- |
| `blender/micro15_world.blend` | The world scene (Blender 5.2). |
| `blender/build_world.py` | Rebuilds the whole scene from OpenStreetMap data. |
| `reference/micro15_osm.json` | OpenStreetMap extract (700 m around the Micro 15 node). © OpenStreetMap contributors, ODbL. |

The map covers about 1.2 km × 1.2 km, 1 unit = 1 metre, +Y = north. It holds
roads with sidewalks and centre lines, footpaths and cycle lanes, parks,
playgrounds, sports pitches, parking lots, around 340 non-enterable buildings
(215 blocks of flats, houses, garages, schools, the hospital, two churches,
shops), about 2,900 trees and bushes, street lamps and benches. There are no
cars or people.

Buildings without a storey count in OSM get one from their footprint: compact
blocks become P+10 towers, long slabs become P+4. Each building object keeps
its `osm_id`, `kind` and `levels` as custom properties so it can be fixed by
hand.

### Rebuilding

In Blender's Python console (or the Blender MCP):

```python
import sys; sys.path.insert(0, r"<repo>/blender")
import build_world; build_world.build_all(r"<repo>")
```

Each stage (`stage_scene`, `stage_ground`, `stage_roads`,
`stage_buildings`, `stage_vegetation`, `stage_cameras`) can be rerun on its
own; it clears and rebuilds only its own collections.

### Notes for the game engine

* Materials are EEVEE node trees (Shader to RGB). Each material's viewport
  colour holds its flat colour, so an exporter or engine toon shader can use
  that.
* Outlines are Solidify modifiers named `Outline` (flipped, back-face culled
  shell using `M15_outline`). Apply or drop them on export, depending on how
  the engine draws outlines.
* Trees, lamps and benches share mesh data (instances) from the hidden
  `M15_Prototypes` collection.
