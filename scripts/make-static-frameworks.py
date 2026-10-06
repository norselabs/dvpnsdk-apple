#!/usr/bin/env python3
"""Re-packages a static-library xcframework (<slice>/lib.a + Headers/) as static *.framework bundles.

Xcode's ProcessXCFramework step copies a library-style xcframework's headers into the shared
$(BUILT_PRODUCTS_DIR)/include/ directory, so two such frameworks that both ship a module.modulemap
(LibXray, LibHysteria, Tun2SocksKit's HevSocks5Tunnel) collide with "Multiple commands produce
.../include/module.modulemap". Framework-style slices keep their headers and module map inside the
bundle, which is what gomobile used to produce.

Usage: make-static-frameworks.py <in.xcframework> <out.xcframework> <ModuleName> <umbrella header>
"""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

PLATFORM_KEYS = {
    "ios": ("MinimumOSVersion", ["iPhoneOS"]),
    "tvos": ("MinimumOSVersion", ["AppleTVOS"]),
    "macos": ("LSMinimumSystemVersion", ["MacOSX"]),
}
MIN_VERSIONS = {"ios": "18.0", "tvos": "18.0", "macos": "15.0"}


def make_framework(slice_dir, lib_path, headers_dir, name, umbrella, platform, variant, out_dir):
    fw = os.path.join(out_dir, f"{name}.framework")
    os.makedirs(fw)
    if platform == "macos":
        versions = os.path.join(fw, "Versions", "A")
        os.makedirs(os.path.join(versions, "Resources"))
        root = versions
    else:
        root = fw

    shutil.copy2(lib_path, os.path.join(root, name))
    shutil.copytree(headers_dir, os.path.join(root, "Headers"), ignore=shutil.ignore_patterns("module.modulemap"))
    os.makedirs(os.path.join(root, "Modules"))
    with open(os.path.join(root, "Modules", "module.modulemap"), "w") as f:
        f.write(f"framework module {name} {{\n  umbrella header \"{umbrella}\"\n  export *\n  module * {{ export * }}\n}}\n")

    min_key, supported = PLATFORM_KEYS[platform]
    if variant == "simulator":
        supported = [p.replace("OS", "Simulator") for p in supported]
    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": name,
        "CFBundleIdentifier": f"io.norselabs.{name}",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": name,
        "CFBundlePackageType": "FMWK",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "CFBundleSupportedPlatforms": supported,
        min_key: MIN_VERSIONS[platform],
    }
    info_path = os.path.join(root, "Resources", "Info.plist") if platform == "macos" else os.path.join(root, "Info.plist")
    with open(info_path, "wb") as f:
        plistlib.dump(info, f)

    if platform == "macos":
        os.symlink("A", os.path.join(fw, "Versions", "Current"))
        for entry in (name, "Headers", "Modules", "Resources"):
            os.symlink(os.path.join("Versions", "Current", entry), os.path.join(fw, entry))
    return fw


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    src, dst, name, umbrella = sys.argv[1:]
    with open(os.path.join(src, "Info.plist"), "rb") as f:
        info = plistlib.load(f)

    workdir = tempfile.mkdtemp(prefix="static-frameworks-")
    cmd = ["xcodebuild", "-create-xcframework"]
    for lib in info["AvailableLibraries"]:
        slice_dir = os.path.join(src, lib["LibraryIdentifier"])
        lib_path = os.path.join(slice_dir, lib["LibraryPath"])
        headers_dir = os.path.join(slice_dir, lib.get("HeadersPath", "Headers"))
        out_dir = os.path.join(workdir, lib["LibraryIdentifier"])
        os.makedirs(out_dir)
        fw = make_framework(slice_dir, lib_path, headers_dir, name, umbrella,
                            lib["SupportedPlatform"], lib.get("SupportedPlatformVariant"), out_dir)
        cmd += ["-framework", fw]

    tmp_out = os.path.join(workdir, os.path.basename(dst))
    cmd += ["-output", tmp_out]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    if os.path.abspath(src) == os.path.abspath(dst):
        shutil.rmtree(src)
    elif os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.move(tmp_out, dst)
    shutil.rmtree(workdir)
    print(f"Wrote framework-style {dst}")


if __name__ == "__main__":
    main()
