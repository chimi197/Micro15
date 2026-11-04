# What the real Micro 15 looks like

The map was built from OpenStreetMap, which gets the streets and the blocks
in the right places but says little about what it is like to stand in a
yard. To match the real place, the neighbourhood was studied from above and
from the street (November 2026). The full notes are in
[`reference/micro15_observations.md`](../reference/micro15_observations.md).

## Sources

* **From above**: Esri World Imagery at zoom 18 (about 0.4 m a pixel, a
  summer picture in full leaf; zoom 19 is not available here), stitched
  into `reference/satellite/micro15_z18.png` with its corners in
  `bounds.json`. Its licence does not allow putting it in the repository,
  so it is only on Johnny's PC.
* **From the street**: eleven Wikimedia Commons photos of the boulevards,
  side streets, a bridge and an Ikarus bus (mostly Panoramio photos by
  Szemes Elek, CC BY-SA 3.0), in `reference/photos/` on the PC with their
  sources and licences in `reference/photos/sources.md`. None shows the
  inside of a Micro 15 yard.

## What the game should get right

1. Wide, straight Careiului with tall blocks, shops in the ground floors and
   parking in front, against the leafy, quiet yards behind them.
2. **Trees far outnumber open lawn inside the yards**: big limes, chestnuts,
   poplars and birches with crowns 10 to 15 m across, as tall as a four
   storey block, shading most paths.
3. Every block is a patchwork: roofs redone one stairwell at a time in red
   or blue, insulation put on flat by flat, balconies closed in by each
   family in their own way.
4. Cars and garages everywhere: rows of rusty-roofed garages, gravel lots,
   cars half on the kerb.
5. Small playgrounds with sand and metal frames between two blocks, dirt
   shortcuts across the lawns, kiosks by the parking lots.
6. Red-tiled houses start right at Dariu Pop to the south, and a few old
   ones survive inside the district.
7. Landmarks: the hospital with its helipad lawn, the two roundabouts (the
   Careiului / Lalelei one with crossings on red asphalt), the market roof,
   the reformed church.

## What changed in the game because of it

* **Tree canopy.** Measured on a 1 m grid over the playable area, the real
  tree cover is about 58 % of the ground seen from above; the game had
  about 7 %. `tools/satellite_trees.py` compares the two and plants trees
  where the real canopy is and the game had none, keeping clear of
  buildings, roads and your paths: 1,666 trees (tree_a, tree_b and tree_c,
  a little bigger than before, since the real crowns are), which brings
  the game to about 49 % and covers two thirds of the real canopy. They are
  ordinary map trees: the map editor removes or moves them like any other.
  Their list is `game/levels/micro15/props_satellite.json`, and
  `python tools/satellite_trees.py --remove` takes them all out again.
  `--png` draws the comparison.
* **Worn paths.** A "Worn path" type for the map editor's path tool (0.8 m,
  bare earth, barely raised) for the shortcuts kids wear across the lawns.
  The real ones are mostly under the canopy in the summer picture, so they
  are left for you to draw where you remember them.
* **Unseen neighbours.** The yards are lived in, but the game has no
  people: somebody beating a carpet, a ball against a wall, a stairwell
  door, a window shutting, played at the buildings round the boy at the
  hours they would happen ([playing](playing.md#sound)).
* **Kiosks, playgrounds, benches** became usable ([playing](playing.md)).

## Still to do from the research

* Roof patches per stairwell and flat-by-flat insulation on the facades
  (needs a per-flat layout from `blender/build_map.py`, so the patches line
  up with the windows).
* Garage rows with rust-brown roofs and gravel parking lots where the
  picture shows them, red asphalt under the crossings at the Lalelei
  roundabout.
* The helipad circle on the hospital lawn, the old houses inside the
  district.
* Yard-level references: Street View or your own memory and photos would
  show what the satellite cannot (the yard between the blocks, the colour
  of each block).
