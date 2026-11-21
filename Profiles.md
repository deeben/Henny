# Compatibility profiles

Some Windows programs need particular settings to run well in Henny: extra launch arguments, a
DLL kept out, DXVK off, a non-zero DPI. Rather than everyone finding these by trial and error,
Henny keeps them in one file, [`profiles.json`](HennyKit/Sources/HennyKit/Resources/profiles.json),
and applies them by itself when you open a program it knows.

## What Henny does with it

- **Every launch, silently:** a matching profile's `arguments`, `environment` and `dllOverrides`
  are added to the program's own settings. Anything you set yourself in the program's settings wins.
- **The first time you open the program:** if the profile wants bottle-wide changes (graphics,
  Windows version, sync, AVX, DPI, Retina, registry values or Winetricks verbs) and the bottle doesn't
  have them yet, Henny lists them and asks: *Apply and Open*, *Open Without Changes*, or *Cancel*.
  It asks again only if the profile's setup changes later.
- **Winetricks** runs in Terminal so you can watch it. Open the program again once it finishes.

Programs are matched by file name, ignoring case (`steam.exe` matches `Steam.exe`). The first
profile listing the name whose runtime range includes the installed runtime is used.

## Where the file comes from

Henny ships with a copy built in, so profiles work offline. When Henny starts it also fetches
`https://henny.deezlepower.com/Wine/profiles.json` (the same place as the Wine runtime) and keeps
it if its `revision` is higher. That request carries no account, ID or information about your
programs; it is a plain download, like the runtime update check.

## Format

```json
{
  "format": 1,
  "revision": 2,
  "updated": "2026-11-21",
  "profiles": [
    {
      "id": "steam",
      "name": "Steam",
      "programs": ["steam.exe"],
      "minRuntime": "11.33.0",
      "arguments": [],
      "environment": {},
      "dllOverrides": {},
      "bottle": { "graphics": "d3dmetal", "dpi": 96 },
      "registry": [],
      "winetricks": [],
      "notice": null,
      "notes": "Why these settings are needed.",
      "tested": { "runtime": "11.33.0", "date": "2026-11-21", "result": "works", "with": "store and login" }
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `format` | File format version. Only bumped for changes older copies of Henny can't read. |
| `revision` | Bump by one on every change. Henny keeps the copy with the highest revision. |
| `id` | Lower-case, dashes allowed, never reused. |
| `programs` | Executable file names the profile applies to. |
| `minRuntime`, `runtimeBelow` | Optional runtime range (`HennyWineVersion.plist`). Use two profiles for the same program when older runtimes need different settings. |
| `arguments` | Added to the program's command line, one argument per entry. |
| `environment` | Environment variables. DLL overrides go in `dllOverrides`, not here. |
| `dllOverrides` | DLL name to load order: `n`, `b`, `n,b`, `b,n`, or `d` to disable. Added after the bottle's own (DXVK's). |
| `bottle.graphics` | `d3dmetal` (DXVK off) or `dxvk`. `wined3d` is reserved and ignored for now. |
| `bottle.windowsVersion` | `win7`, `win8`, `win81`, `win10`, `win11`, `winxp64`. |
| `bottle.enhancedSync` | `none`, `esync` or `msync`. |
| `bottle.avx`, `bottle.retina` | `true` or `false`. |
| `bottle.dpi` | Windows DPI. Chromium-based programs draw nothing at 0. |
| `registry` | Values to set once, each with `key` (starting `HKCU\` or `HKLM\`), `name`, `type` (`REG_SZ`, `REG_DWORD`, ...) and `data`. |
| `winetricks` | Winetricks verbs to install once (asked first; runs with `-q`). |
| `notice` | Shown once when the program is first opened, for a known problem with no setting to fix it. |
| `notes` | For people reading the file: why. Not shown in the app. |
| `tested` | `runtime`, `date`, `result` (`works`, `partial`, `broken`) and optionally `with` (what you tried). |

Settings Henny already sets for every program, such as `WINE_SIMULATE_WRITECOPY=1` and
`CX_APPLEGPTK_LIBD3DSHARED_PATH`, don't need repeating in a profile.

## Adding or changing a profile

1. Get the program working by hand in a fresh bottle, and write down only the settings that turned
   out to matter.
2. Add or edit its entry, bump `revision` and `updated`, and fill in `tested`.
3. Run `python3 scripts/check-profiles.py`. The same check runs on every pull request.
4. Open a pull request saying what you tested, on which Mac and runtime.

Once merged, a maintainer publishes it with `scripts/publish-profiles.sh`, which checks the file,
refuses a revision that isn't higher than the live one, and uploads it to R2. The next Henny
release carries it built in.
