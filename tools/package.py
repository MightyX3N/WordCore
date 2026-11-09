#!/usr/bin/env python3
"""
Make the downloadable zips from the builds in dist/.

    python tools/package.py

Creates dist/packages/:
  wordcore-<version>-shared-hosting.zip  upload + extract on shared hosting (Linux x86_64, CGI)
  wordcore-<version>-<target>.zip      run on your own computer
"""
import stat
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
HOST = ROOT / "runtime" / "host"
OUT = DIST / "packages"
NOTICES = ROOT / "runtime" / "vendor" / "NOTICES.txt"

EXEC = (stat.S_IFREG | 0o755) << 16
FILE = (stat.S_IFREG | 0o644) << 16
DIR = (stat.S_IFDIR | 0o755) << 16


def add(z, arcname, data, mode):
    info = zipfile.ZipInfo(arcname, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = mode
    info.create_system = 3  # Unix, so permissions are kept when extracted
    z.writestr(info, data)


def add_dir(z, arcname):
    info = zipfile.ZipInfo(arcname.rstrip("/") + "/", date_time=(2026, 1, 1, 0, 0, 0))
    info.external_attr = DIR | 0x10
    info.create_system = 3
    z.writestr(info, b"")


def main():
    version = (ROOT / "runtime" / "VERSION").read_text().strip()
    OUT.mkdir(parents=True, exist_ok=True)
    made = []

    linux = DIST / "linux-x86_64" / "wordcore"
    if not linux.exists():
        sys.exit("Build first: python runtime/build/build.py")

    host_zip = OUT / f"wordcore-{version}-shared-hosting.zip"
    with zipfile.ZipFile(host_zip, "w") as z:
        d = "wordcore/"
        add_dir(z, d)
        add(z, d + "wordcore.cgi", linux.read_bytes(), EXEC)
        add(z, d + ".htaccess", (HOST / "htaccess").read_bytes(), FILE)
        add_dir(z, d + "public")
        add(z, d + "public/README.txt", b"Files in this folder are served directly by your web server.\n", FILE)
        add_dir(z, d + "site")
        add(z, d + "site/.htaccess", (HOST / "site-htaccess").read_bytes(), FILE)
        add(z, d + "README.txt", (HOST / "README.txt").read_bytes(), FILE)
        add(z, d + "NOTICES.txt", NOTICES.read_bytes(), FILE)
    made.append(host_zip)

    for target in sorted(p.name for p in DIST.iterdir() if p.is_dir() and p.name != "packages"):
        exe_name = "wordcore.exe" if target.startswith("windows") else "wordcore"
        exe = DIST / target / exe_name
        if not exe.exists():
            continue
        zpath = OUT / f"wordcore-{version}-{target}.zip"
        with zipfile.ZipFile(zpath, "w") as z:
            d = f"wordcore-{version}/"
            add_dir(z, d)
            add(z, d + exe_name, exe.read_bytes(), EXEC)
            readme = (HOST / "LOCAL-README.txt").read_text()
            if target.startswith("windows"):
                readme = readme.replace("\n", "\r\n")
            add(z, d + "README.txt", readme.encode(), FILE)
            add(z, d + "NOTICES.txt", NOTICES.read_bytes(), FILE)
        made.append(zpath)

    for p in made:
        print(f"{p.relative_to(ROOT)}  {p.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
