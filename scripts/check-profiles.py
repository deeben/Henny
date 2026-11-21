#!/usr/bin/env python3
"""Checks Henny's compatibility profiles file before it is merged or uploaded.

Usage: python3 scripts/check-profiles.py [path/to/profiles.json]
Exits non-zero and prints each problem when the file is not valid.
"""
import json
import re
import sys

DEFAULT_PATH = "HennyKit/Sources/HennyKit/Resources/profiles.json"
SUPPORTED_FORMAT = 1

PROFILE_KEYS = {
    "id", "name", "programs", "minRuntime", "runtimeBelow", "arguments", "environment",
    "dllOverrides", "bottle", "registry", "winetricks", "notice", "notes", "tested",
}
BOTTLE_KEYS = {"graphics", "windowsVersion", "enhancedSync", "avx", "dpi", "retina"}
GRAPHICS = {"d3dmetal", "dxvk", "wined3d"}
WINDOWS = {"winxp64", "win7", "win8", "win81", "win10", "win11"}
SYNC = {"none", "esync", "msync"}
REG_TYPES = {"REG_SZ", "REG_DWORD", "REG_QWORD", "REG_BINARY"}
RESULTS = {"works", "partial", "broken"}
DLL_ORDERS = {"n", "b", "n,b", "b,n", "d", ""}
VERSION = re.compile(r"^\d+\.\d+\.\d+$")
ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def version(text):
    return tuple(int(part) for part in text.split("."))


def check(catalog):
    problems = []
    if catalog.get("format") != SUPPORTED_FORMAT:
        problems.append(f"format must be {SUPPORTED_FORMAT}")
    if not isinstance(catalog.get("revision"), int) or catalog["revision"] < 1:
        problems.append("revision must be a whole number of 1 or more")
    profiles = catalog.get("profiles")
    if not isinstance(profiles, list) or not profiles:
        return problems + ["profiles must be a non-empty list"]

    seen_ids = set()
    ranges = {}  # program name -> [(id, low, high)]
    for index, profile in enumerate(profiles):
        where = f"profiles[{index}] ({profile.get('id', '?')})"
        problems += [f"{where}: unknown field '{key}'" for key in profile.keys() - PROFILE_KEYS]

        pid = profile.get("id")
        if not isinstance(pid, str) or not ID.match(pid):
            problems.append(f"{where}: id must be lower-case letters, digits and dashes")
        elif pid in seen_ids:
            problems.append(f"{where}: id is used twice")
        seen_ids.add(pid)

        programs = profile.get("programs")
        if not isinstance(programs, list) or not programs or not all(
            isinstance(name, str) and name.lower().endswith(".exe") for name in programs
        ):
            problems.append(f"{where}: programs must list .exe file names")
            programs = []

        low, high = (0, 0, 0), (999999, 0, 0)
        for key in ("minRuntime", "runtimeBelow"):
            value = profile.get(key)
            if value is None:
                continue
            if not isinstance(value, str) or not VERSION.match(value):
                problems.append(f"{where}: {key} must look like 11.33.0")
            elif key == "minRuntime":
                low = version(value)
            else:
                high = version(value)
        if low >= high:
            problems.append(f"{where}: minRuntime must be lower than runtimeBelow")
        for name in programs:
            for other, other_low, other_high in ranges.get(name.lower(), []):
                if low < other_high and other_low < high:
                    problems.append(
                        f"{where}: {name} is also in '{other}' for the same runtimes; only the first would apply"
                    )
            ranges.setdefault(name.lower(), []).append((pid, low, high))

        arguments = profile.get("arguments", [])
        if not isinstance(arguments, list) or not all(isinstance(a, str) and a and " " not in a for a in arguments):
            problems.append(f"{where}: arguments must be a list of single arguments without spaces")

        environment = profile.get("environment", {})
        if not isinstance(environment, dict) or not all(isinstance(v, str) for v in environment.values()):
            problems.append(f"{where}: environment values must be strings")
        elif "WINEDLLOVERRIDES" in environment:
            problems.append(f"{where}: put DLL overrides in dllOverrides, not environment")

        overrides = profile.get("dllOverrides", {})
        if not isinstance(overrides, dict) or not all(
            isinstance(v, str) and v.replace(" ", "") in DLL_ORDERS for v in overrides.values()
        ):
            problems.append(f"{where}: dllOverrides values must be n, b, n,b, b,n or d")

        bottle = profile.get("bottle", {})
        if not isinstance(bottle, dict):
            problems.append(f"{where}: bottle must be an object")
            bottle = {}
        problems += [f"{where}: unknown bottle field '{key}'" for key in bottle.keys() - BOTTLE_KEYS]
        for key, allowed in (("graphics", GRAPHICS), ("windowsVersion", WINDOWS), ("enhancedSync", SYNC)):
            if key in bottle and bottle[key] not in allowed:
                problems.append(f"{where}: bottle.{key} must be one of {', '.join(sorted(allowed))}")
        for key in ("avx", "retina"):
            if key in bottle and not isinstance(bottle[key], bool):
                problems.append(f"{where}: bottle.{key} must be true or false")
        if "dpi" in bottle and (not isinstance(bottle["dpi"], int) or not 72 <= bottle["dpi"] <= 480):
            problems.append(f"{where}: bottle.dpi must be between 72 and 480")

        for value in profile.get("registry", []):
            if set(value) != {"key", "name", "type", "data"} or not all(isinstance(v, str) for v in value.values()):
                problems.append(f"{where}: each registry value needs key, name, type and data as strings")
            elif value["type"] not in REG_TYPES or not value["key"].startswith(("HKCU\\", "HKLM\\")):
                problems.append(f"{where}: registry key must start with HKCU\\ or HKLM\\ and type be a REG_ type")

        verbs = profile.get("winetricks", [])
        if not isinstance(verbs, list) or not all(isinstance(v, str) and re.match(r"^[A-Za-z0-9_.=-]+$", v) for v in verbs):
            problems.append(f"{where}: winetricks must list verb names")

        tested = profile.get("tested")
        if not isinstance(tested, dict) or tested.get("result") not in RESULTS:
            problems.append(f"{where}: tested.result must be works, partial or broken")
        elif not VERSION.match(str(tested.get("runtime", ""))):
            problems.append(f"{where}: tested.runtime must be the runtime version you tested with")
    return problems


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH
    try:
        with open(path, encoding="utf-8") as file:
            catalog = json.load(file)
    except (OSError, json.JSONDecodeError) as error:
        print(f"{path}: {error}")
        return 1
    problems = check(catalog)
    for problem in problems:
        print(f"{path}: {problem}")
    if not problems:
        print(f"{path}: {len(catalog['profiles'])} profiles, revision {catalog['revision']}, OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
