#!/usr/bin/env python3
"""Writes CREDITS.md: every piece of third-party code this package carries or links, with its licence and home.

    scripts/gen-credits.py           write CREDITS.md
    scripts/gen-credits.py --check   fail when the committed CREDITS.md is out of date (scripts/check.sh)

Sources: the Swift packages in Package.resolved (licence files from the checkouts `swift build` or scripts/test.sh
made), the vendored WireGuardKit and its Go bridge, and the licence inventory each engine's build writes next to it
(Frameworks/<name>.licenses.json). A licence text this script does not recognise stops it: a new dependency is
reviewed, not listed blind.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "CREDITS.md")
ENGINES = ["LibXray", "LibHysteria", "HevSocks5Tunnel", "WireGuardKitGo"]
CHECKOUTS = [os.path.join(ROOT, ".build", d, "checkouts") for d in ("test", "")]
LICENSE_FILE = re.compile(r"^(licen[cs]e|copying)([-._].*)?$", re.I)
# Packages used only while building (macros), which nothing ships.
BUILD_ONLY = {"swift-syntax"}
# Modules changed here before they are built in, and where the change is.
PATCHED = {
    "github.com/xtls/xray-core": "GoBridge/xray-core",
    "github.com/xtls/reality": "GoBridge/reality",
}


def classify(name, text):
    """The SPDX identifiers a licence file grants; None when it is not recognised."""
    t = " ".join(text.lower().split())
    ids = []
    if "mozilla public license version 2.0" in t:
        ids.append("MPL-2.0")
    if "apache license" in t and "version 2.0" in t:
        ids.append("Apache-2.0")
    if "permission is hereby granted, free of charge" in t:
        ids.append("MIT")
    if "redistribution and use in source and binary forms" in t:
        named = re.search(r"neither the name|names of (its|the) contributors|name of the author may not be used", t)
        ids.append("BSD-3-Clause" if named else "BSD-2-Clause")
    if "permission to use, copy, modify, and/or distribute this software for any purpose" in t:
        ids.append("ISC")
    if "this is free and unencumbered software released into the public domain" in t:
        ids.append("Unlicense")
    return ids or None


def expression(files, owner):
    ids = []
    for name, text in files:
        found = classify(name, text)
        if found is None:
            sys.exit(f"gen-credits: {owner}: {name} is a licence this script does not recognise; review it and teach classify()")
        ids += [i for i in found if i not in ids]
    if not ids:
        sys.exit(f"gen-credits: {owner}: no licence file")
    return " AND ".join(ids)


def module_link(path):
    repo = re.match(r"^github\.com/[^/]+/[^/]+", path)
    return f"https://{repo.group(0)}" if repo else f"https://pkg.go.dev/{path}"


def swift_packages():
    resolved = json.load(open(os.path.join(ROOT, "Package.resolved")))
    checkouts = next((d for d in CHECKOUTS if os.path.isdir(d)), None)
    if checkouts is None:
        sys.exit("gen-credits: no package checkouts: run scripts/test.sh (or swift build) first")
    rows = []
    for pin in resolved["pins"]:
        identity, location = pin["identity"], pin["location"].removesuffix(".git")
        directory = os.path.join(checkouts, os.path.basename(location))
        if not os.path.isdir(directory):
            sys.exit(f"gen-credits: {identity} is not checked out in {checkouts}: resolve the package first")
        files = [(f, open(os.path.join(directory, f), errors="replace").read())
                 for f in sorted(os.listdir(directory)) if LICENSE_FILE.match(f)]
        use = "building only (macros)" if identity in BUILD_ONLY else "the package"
        rows.append((identity, pin["state"].get("version") or pin["state"]["revision"][:12], expression(files, identity),
                     location, use))
    return rows


def vendored():
    copying = open(os.path.join(ROOT, "Sources/WireGuardKit/COPYING")).read()
    licence = expression([("COPYING", copying)], "WireGuardKit")
    home = "https://github.com/amnezia-vpn/amneziawg-apple"
    return [
        ("WireGuardKit (WireGuard LLC, as amneziawg-apple ships it)", "3.1.4", licence, home,
         "`Sources/WireGuardKit`, `Sources/WireGuardKitC`"),
        ("WireGuardKit's Go bridge", "3.1.4", licence, home, "`GoBridge/wireguard`, built into WireGuardKitGo"),
    ]


def engine_modules():
    merged = {}
    for engine in ENGINES:
        path = os.path.join(ROOT, "Frameworks", f"{engine}.licenses.json")
        if not os.path.exists(path):
            sys.exit(f"gen-credits: {path} is missing: build the engine with its scripts/build-*.sh")
        inventory = json.load(open(path))
        modules = list(inventory["modules"])
        if inventory.get("go"):
            modules.append(dict(inventory["go"], path="Go"))
        for module in modules:
            entry = merged.setdefault(module["path"], {"versions": [], "files": [], "engines": []})
            if module["version"] not in entry["versions"]:
                entry["versions"].append(module["version"])
            for licence in module["licenses"]:
                pair = (os.path.basename(licence["name"]), licence["text"])
                if pair not in entry["files"]:
                    entry["files"].append(pair)
            if engine not in entry["engines"]:
                entry["engines"].append(engine)
    rows = []
    for path, entry in sorted(merged.items(), key=lambda item: item[0].lower()):
        link = "https://go.dev" if path == "Go" else module_link(path)
        use = ", ".join(entry["engines"])
        if path in PATCHED:
            use += f"; changed by the patches in `{PATCHED[path]}`"
        rows.append((path, ", ".join(sorted(entry["versions"])), expression(entry["files"], path), link, use))
    return rows


def table(rows):
    lines = ["| Dependency | Version | Licence | Link | Used in |", "|---|---|---|---|---|"]
    lines += [f"| {name} | {version} | {licence} | <{link}> | {use} |" for name, version, licence, link, use in rows]
    return "\n".join(lines)


def main():
    text = f"""# Credits

The DVPN SDK is built on the work of others. Each piece of third-party code it carries or links is listed below with
its licence; that licence, not the SDK's ([LICENSE.md](LICENSE.md), section 8), governs it. The engines' own
dependencies come from their builds' licence inventories, `Frameworks/<name>.licenses.json`, which every release also
carries with the full licence texts.

This file is generated by `scripts/gen-credits.py`; do not edit it by hand.

## Swift packages

{table(swift_packages())}

## Vendored source

{table(vendored())}

## Engines and what they link

{table(engine_modules())}
"""
    if "--check" in sys.argv:
        current = open(OUTPUT).read() if os.path.exists(OUTPUT) else ""
        if current != text:
            sys.exit("gen-credits: CREDITS.md is out of date: run scripts/gen-credits.py")
        print("CREDITS.md is current")
    else:
        open(OUTPUT, "w").write(text)
        print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
