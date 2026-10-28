# What has changed

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
