#!/usr/bin/env python3
"""Make a copied barrel runtime relocatable.

For every Mach-O file under RUNTIME:
- dependencies and install ids that point inside BUILD_ROOT become @rpath/<name>;
- rpaths that point inside BUILD_ROOT are replaced by one @loader_path-relative rpath to RUNTIME/deps/lib;
- the file is ad-hoc signed again (install_name_tool invalidates signatures).

Then it fails if any Mach-O still references BUILD_ROOT.

usage: relocate_runtime.py RUNTIME BUILD_ROOT
"""
import os
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def is_macho(path):
    with open(path, "rb") as f:
        magic = f.read(4)
    return magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def load_commands(path):
    """Returns (install id or None, dependencies, rpaths)."""
    ident, deps, rpaths = None, [], []
    lines = run("otool", "-l", path).splitlines()
    for i, line in enumerate(lines):
        cmd = line.strip()
        if cmd in ("cmd LC_ID_DYLIB", "cmd LC_LOAD_DYLIB", "cmd LC_LOAD_WEAK_DYLIB", "cmd LC_RPATH"):
            for follow in lines[i + 1:i + 4]:
                follow = follow.strip()
                if follow.startswith("name ") or follow.startswith("path "):
                    value = follow.split(" ", 1)[1].rsplit(" (offset", 1)[0]
                    if cmd == "cmd LC_ID_DYLIB":
                        ident = value
                    elif cmd == "cmd LC_RPATH":
                        rpaths.append(value)
                    else:
                        deps.append(value)
                    break
    return ident, deps, rpaths


def main():
    runtime, build_root = (os.path.realpath(p) for p in sys.argv[1:3])
    deps_lib = os.path.join(runtime, "deps", "lib")
    files = [os.path.join(d, f) for d, _, names in os.walk(runtime) for f in names]
    machos = [f for f in files if os.path.isfile(f) and not os.path.islink(f) and is_macho(f)]

    for path in machos:
        ident, deps, rpaths = load_commands(path)
        args = []
        if ident and ident.startswith(build_root):
            args += ["-id", "@rpath/" + os.path.basename(ident)]
        for dep in deps:
            if dep.startswith(build_root):
                args += ["-change", dep, "@rpath/" + os.path.basename(dep)]
        stale = [r for r in rpaths if r.startswith(build_root)]
        for r in stale:
            args += ["-delete_rpath", r]
        if args:
            relative = os.path.relpath(deps_lib, os.path.dirname(path))
            wanted = "@loader_path/" + relative
            if wanted not in rpaths:
                args += ["-add_rpath", wanted]
            run("install_name_tool", *args, path)
            run("codesign", "--force", "--sign", "-", path)

    leftovers = []
    for path in machos:
        ident, deps, rpaths = load_commands(path)
        if any(v and v.startswith(build_root) for v in [ident, *deps, *rpaths]):
            leftovers.append(path)
    print(f"relocated {len(machos)} Mach-O files under {runtime}")
    if leftovers:
        print("still referencing the build tree:", *leftovers, sep="\n  ")
        sys.exit(1)


if __name__ == "__main__":
    main()
