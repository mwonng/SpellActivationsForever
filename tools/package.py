"""Build the release zip CurseForge and WoWInterface accept: a top-level SpellActivationsForever/ folder holding
only the files the game needs, with the version stamped into the .toc.

    python tools/package.py            -> version from the latest git tag (v0.1.0 -> 0.1.0)
    python tools/package.py 0.2.0      -> that version

Writes dist/SpellActivationsForever-<version>.zip
"""
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "SpellActivationsForever"
FILES = ["SpellActivationsForever.toc", "spells.lua", "core.lua", "options.lua", "README.md", "CHANGELOG.md"]


def version():
    if len(sys.argv) > 1:
        return sys.argv[1].lstrip("v")
    tag = subprocess.check_output(["git", "describe", "--tags", "--abbrev=0"], cwd=ROOT, text=True).strip()
    return tag.lstrip("v")


def main():
    ver = version()
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", f"{NAME}-{ver}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in FILES:
            path = os.path.join(ROOT, name)
            if name.endswith(".toc"):
                with open(path, encoding="utf-8") as f:
                    toc = f.read()
                toc = re.sub(r"^## Version: .*$", f"## Version: {ver}", toc, flags=re.M)
                z.writestr(f"{NAME}/{name}", toc)
            else:
                z.write(path, f"{NAME}/{name}")
    print("wrote", os.path.relpath(out, ROOT), "version", ver)


if __name__ == "__main__":
    main()
