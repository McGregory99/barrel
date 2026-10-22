# Barrel recipe format (version 1)

A recipe is a JSON file describing how to prepare a bottle for an application: bottle
settings, dependencies on other recipes, and ordered steps. The format is open and
original to this project (it is not CodeWeavers' CrossTie/C4P format).

```json
{
  "formatVersion": 1,
  "id": "windows-app-base",
  "name": "Windows app base",
  "description": "optional",
  "notes": "optional",
  "bottle": { "windowsVersion": "win10", "graphicsBackend": "wined3d", "msync": true },
  "dependencies": ["vcredist-x64"],
  "steps": [ ... ]
}
```

| Field | Rules |
|---|---|
| `formatVersion` | required, must be `1` |
| `id` | required; lowercase letters, digits, `.` `-` `_`; unique across recipe directories |
| `name`, `description` | `name` required, `description` optional: one or two sentences shown to users in the app's Install Software sheet |
| `notes` | optional, for recipe maintainers (why a fix exists, how to refresh a pinned hash); never shown in the app |
| `bottle` | optional. `windowsVersion` (`barrel templates`), `graphicsBackend` (`wined3d`, `dxvk`, `dxmt`, `d3dmetal`), `msync` (bool), `appGraphics` (object of executable file name → `wined3d`/`dxvk`/`dxmt`, applied after `graphicsBackend`, e.g. `{"steamwebhelper.exe": "wined3d"}`). Only the recipe you install applies these; dependencies' `bottle` blocks are ignored. `windowsVersion` is used only when the bottle is created. |
| `dependencies` | ids of recipes installed first, each once, in dependency order. Unknown ids and cycles are errors. |
| `steps` | run in order, numbered from 1 in error messages |

## Steps

Each step has a `kind`.

- `download`: `url` (http/https), `sha256` (required, 64 hex characters, always verified), `fileName`
  (plain file name). The file is cached in `$BARREL_HOME/Downloads/<fileName>`; a cached file whose hash
  matches is never downloaded again. A mismatch deletes the download and fails the install.
- `run`: either `file` (the `fileName` of an earlier download step in the same recipe) or `path` (a Unix
  path, or `C:\...` which maps to the bottle's `drive_c`). Optional `arguments` (silent-install flags) and
  `expectedExitCodes` (default `[0]`); any other exit status fails the install.
- `registry`: `key` (starts with `HKCU\`, `HKLM\`, ...), `name`, `type` (`REG_SZ` default, or `REG_DWORD`),
  `data` (string, or integer for `REG_DWORD`). Applied with the prefix's `reg.exe add ... /f`.
- `dllOverride`: `dll` (bare name, no `.dll` required) and `mode`: `native`, `builtin`, `native,builtin`,
  `builtin,native` or `disabled`. Written to `HKCU\Software\Wine\DllOverrides` with `reg.exe`
  (`disabled` stores an empty value).

## Validation errors

Parsing fails with a precise message for: invalid JSON, missing `formatVersion`/`id`/`name`, unsupported
`formatVersion`, unknown step `kind`, a `download` without `sha256` (or with a malformed one, which is how
examples that still need a hash are rejected), a `run` of a file no earlier `download` provides, bad
override modes, registry keys or `REG_DWORD` data. Dependency problems (unknown recipe, cycle) surface
when installing.

## Usage

```sh
barrel recipes --recipes-dir recipes            # list
barrel install windows-app-base --recipes-dir recipes --bottle Office
```

Recipes are read from `$BARREL_HOME/Recipes` and from `--recipes-dir` (the latter wins on duplicate ids).
Without `--bottle`, a bottle named after the recipe id is used, and created if missing. Recipes are not
sandboxed: `run` steps execute arbitrary code in the bottle, so install only recipes you trust.
