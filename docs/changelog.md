# What has changed

## 2026-11-04: things to do, sound, night and a greener neighbourhood

Following [the audit and roadmap](https://claude.ai/artifact/SU79qButQkqcUjkMs2j5FD).

* **Things to use** ([playing](playing.md)). Benches (placed ones and the
  map's 157), chess table stools and picnic tables to sit on; swings that
  are real pendulums you pump higher; the seesaw; the slide (up the ladder,
  down the chute); leaning on the carpet beater; kiosks and shops with
  opening hours that sell things for bottle caps; a ball at every
  playground, goal and hoop to kick, carry and throw. A prompt shows what
  `E` (X on a pad) does. Nothing is written into the level files: the
  game finds these things when it starts.
* **Bottle caps** to find (60, by benches, playgrounds and kiosks) and
  **memories**: a map editor pin whose note starts with `MEMORY:` becomes a
  story to find and read in the journal.
* **Photo mode** (`V`), the **journal** (Tab), a **pause menu** with
  settings (look speed, invert, field of view, volumes, prompts, camera
  dips) and **saving** (`user://save.json`).
* **Sound**: 68 synthesised sounds. Footsteps by surface, landings, day and
  night ambience, the swing's chains, the ball, caps, the till, and unseen
  neighbours (a carpet being beaten, a ball against a wall, a door, a
  window) at the blocks round the boy.
* **Night**: windows light up one by one, some flicker with a television,
  the street lamps glow and light the ground near the camera, stars and
  the moon come out.
* **Wind**: one breeze with gusts moves the grass and the trees together;
  the grass bends away from the boy's feet.
* **The boy** ([the character](character.md)). The player is split into
  input, camera, animation, foot placement, look-at, face, personality and
  breathing. Walk, jog and sprint blend in step with no sliding feet;
  feet stand on kerbs and slopes; he looks at things nearby and at what
  just happened, blinks, fidgets when left standing, gets out of breath.
  Gamepad support everywhere. His hips are held on seats, so he sits on
  the bench and the swing instead of hovering.
* **The real Micro 15** ([research](research.md)). The neighbourhood was
  studied from satellite pictures and street photos. The yards were far
  too bare: 1,666 trees were planted where the real canopy is, raising tree
  cover from about 7 % to about 49 % (the real one is about 58 %). A
  "Worn path" type was added to the map editor's path tool for the dirt
  shortcuts across the lawns.
* `-- --perf` measures frame times along a route round the play area.

## 2026-10-29: shaping the ground, paths and a seamless edge

* Two new map editor tools. **Terrain** (7) raises, lowers, flattens,
  smooths and resets the ground inside the playable area; trees, grass,
  paths and placed things follow it. **Paths** (8) draws sidewalks with
  kerbs, footpaths and trails.
* The edge is seamless. The whole neighbourhood is drawn again past the
  edge of the playable area, with an invisible wall at the edge. Distant
  blocks of flats and the lawn fade into the horizon beyond the mapped
  streets. The dark blocks are gone.
* The slide was missing its chute in the game. The game hides the back of
  every face, and the chute had been built inside out. Every asset is now
  built facing outwards and checked that way.
* Houses with L-, T- and U-shaped outlines get a flat roof instead of a
  hip roof that floated over their inner corners.
* 15 more assets: gas pipe, electricity cabinet, street name plate, block
  number plate, wall lamp, electricity pole, crossing sign, hydrant,
  manhole cover, advertising column, picnic table, sandbox, seesaw,
  basketball hoop and football goal.
* Faster drawing: the shapeable ground is cut into 64 m pieces instead of
  32 m ones, flat ground casts no shadow, placed trees and bushes use the
  lighter far versions past 70 m, and small placed things stop drawing in
  the distance. `-- --shots` prints the draw calls and triangles of each
  shot, and takes shot names to render only those.
* Footpaths and trails no longer let the ground show through them on
  hillsides.

## 2026-10-28 (evening): the playable area, shops and a tidy repository

* The map is cut to the area set by the CORNER 1 to 4 pins. It keeps the
  streets the corners stand beside: Strada Careiului, Bulevardul Lalelei,
  Strada Oituz and Strada Dariu Pop. 54 buildings stay. See
  [the map](map.md).
* A row of shadowed blocks of flats closes the edge of the area, and the
  player cannot walk or jump past it (`scripts/boundary.gd`). It replaces
  the old invisible walls round the whole map.
* The slide is complete: a slanted ladder with handrails, a railed
  platform and a deep chute with legs.
* Ten new assets, with a new Shops tab in the editor: kiosk, mini market,
  shop window, drinks fridge, ice cream freezer, fruit stall, café table,
  bus stop, recycling bins and a clothes line. See [the assets](assets.md).
* The repository is organised:
  * The README is an overview, and each part has its own page in `docs/`.
  * Screenshots are grouped by subject in `docs/renders/`.
  * Reference pictures are in `reference/`.
  * The level edits made with the map editor are kept in the repository:
    placed things, removed things, grass, pins and the level's look.
* The player starts on Aleea Milcov, inside the new area.

## 2026-10-28: the map editor

* The map editor (F1): select, move and remove anything, including map
  trees, building details and whole buildings.
* Grass brush, pins, coordinates with a grid and a map, and undo and redo.
* Sky & light with presets and a full set of sliders, saved as the level's
  look.
* Kerbs can be walked up.
* Glow is capped, which fixes white blobs on the lawn at golden hour and
  sunset.

## 2026-10-28: art direction

* Soft-lit stylized 3D with no outlines, material families and a muted
  palette ([the art direction](art_direction.md)).
* Trees are modelled leaf by leaf, with far versions for the distance.
* A day cycle following the real sun over Satu Mare.

## 2026-10-27: the first version

* The world was built in Blender from OpenStreetMap.
* A 3D corner test, then the whole map, loaded in Godot.
* The playable boy, rebuilt with a smooth layered body, separate garments
  and a natural rig, with animations retargeted from the CC0 Universal
  Animation Library.
* The editor project and the admin build tool.
