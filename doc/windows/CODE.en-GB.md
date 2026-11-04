# PYMEHackers Control Center (core) for Windows: technical reference

This CODE is also available in:\
en-GB, [en-US](CODE.md), [es-AR](CODE.es-AR.md), [es-ES](CODE.es-ES.md)

Technical status of `app-windows/`. The available desktop implementation and module contract are documented in [CODE](../CODE.en-GB.md).

## Index

1. [Status](#status)
2. [Folder layout](#folder-layout)
3. [Modules on Windows](#modules-on-windows)
4. [What implementing the core would require](#what-implementing-the-core-would-require)

## Status

The PYMEHackers Control Center core is **not implemented on Windows**. `app-windows/` exists only to keep the mandatory folder structure of the project, as recorded in `RulesForThisProjectOnly.md`. It contains no code, no build flow and no installer, so there is no module map, symbol index, call path, route map or installed file to document yet.

## Folder layout

| Folder | Content |
|---|---|
| `frontend/` | Empty |
| `backend/` | Empty |
| `build/` | Empty |
| `tests/` | Empty (the project rules forbid writing tests) |

## Modules on Windows

Modules that support Windows are installed standalone from [PHCC-modules](https://github.com/pymehackers/PHCC-modules): each module documents there its own installer, service and user interface, and works without the core. The `module.json` contract currently supports the desktop platform ids `debian-amd64` and `debian-arm64`, so no catalogue lists Windows support.

## What implementing the core would require

A Windows core must honour the same two contracts as the Debian core: the [module discovery contract](../CODE.en-GB.md#module-discovery-contract) and the [module catalogue contract](../CODE.en-GB.md#module-catalogue-contract).

1. **Menu.** An icon in the notification area (system tray) whose menu has the same structure: header, "Systems", "Cybersecurity", "Module catalogue" and "Quit". Every visible text in `lang/{en-GB,en-US,es-AR,es-ES}.json`, following the user's language, with en-US as default and fallback.
2. **Discovery.** A registry where each module installs a manifest in one folder per section (`sys`, `cs`) with a localised name, an order and a list of actions (label and command), read when the menu is built. No module names in the code. The Windows location and format must be defined and added to the contract of both projects.
3. **Catalogue.** A helper that lists the top-level folders of PHCC-modules with a valid `module.json`, prints the same 7-field lines as `phcc-modules list`, and runs a per-module installer elevated (UAC) only after the user confirms, with no arguments, `--reinstall` or `--uninstall`. A new platform id (for example `windows`) and installer path (for example `<id>/app-windows/build/...`) must be added to the `module.json` contract in `RulesForThisProjectOnly.md` of PHCC and PHCC-modules.
4. **Least privilege.** Only install, update, reinstall and uninstall run elevated, and the repository stays fixed in the helper.
5. **Build and install.** Build scripts in `app-windows/build/` that apply the "core without modules" guard, and an idempotent one-line installer that accepts `--reinstall` and `--uninstall`.
6. **Logs** with UTC dates in the project format (`2026-10-29@13-59-59.723`).
7. **Documentation.** This CODE, the MANUAL and the general documentation, updated in the four languages.
