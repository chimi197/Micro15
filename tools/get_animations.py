"""Downloads Quaternius' Universal Animation Library 1 and 2 (CC0, from
OpenGameArt) and unpacks the two Godot/Unreal .glb files that
blender/retarget_ual.py reads into tools/downloads/ual/.

    python tools/get_animations.py
"""
import os
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tools", "downloads")
PACKS = [
    ("ual1.zip", "https://opengameart.org/sites/default/files/universal_animation_librarystandard.zip",
     "Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb", "UAL1.glb"),
    ("ual2.zip", "https://opengameart.org/sites/default/files/universal_animation_library_2standard.zip",
     "Universal Animation Library 2 [Standard]/Unreal-Godot/UAL2_Standard.glb", "UAL2.glb"),
]


def main():
    os.makedirs(os.path.join(OUT, "ual"), exist_ok=True)
    for zip_name, url, inner, glb in PACKS:
        path = os.path.join(OUT, zip_name)
        if not os.path.exists(path):
            print("downloading", url)
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req) as r, open(path, "wb") as f:
                f.write(r.read())
        with zipfile.ZipFile(path) as z, open(os.path.join(OUT, "ual", glb), "wb") as f:
            f.write(z.read(inner))
        print("unpacked", glb)


if __name__ == "__main__":
    main()
