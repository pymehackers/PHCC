# PYMEHackers Control Center: technical reference

This CODE is also available in:\
en-GB, [en-US](CODE.md), [es-AR](CODE.es-AR.md), [es-ES](CODE.es-ES.md)

Technical reference of PHCC, a desktop application. Debian is the available implementation; macOS and Windows are not implemented yet. Paths in tables are relative to `app-debian/`. See the [user manual](MANUAL.en-GB.md).

## Index

1. [Architecture and design decisions](#architecture-and-design-decisions)
2. [Module map](#module-map)
3. [Key symbol index](#key-symbol-index)
4. [Main call paths](#main-call-paths)
5. [Entry and command map](#entry-and-command-map)
6. [Module discovery contract](#module-discovery-contract)
7. [Module catalogue contract](#module-catalogue-contract)
8. [Language files](#language-files)
9. [Build and packaging](#build-and-packaging)
10. [Files installed on the target system](#files-installed-on-the-target-system)
11. [Change-impact analysis](#change-impact-analysis)
12. [Extension points](#extension-points)
13. [Known limitations](#known-limitations)
14. [Repository layout](#repository-layout)

## Architecture and design decisions

**The core is a menu, not a service.** It places an icon in the top bar whose menu has a header, the two sections "Systems" (`sys`) and "Cybersecurity" (`cs`), the "Module catalogue" submenu and "Quit". It runs no daemon of its own. Modules are separate packages with their own services, published in [PHCC-modules](https://github.com/pymehackers/PHCC-modules); they keep working when the core is not installed or not running, and the core ships with no module inside (the build verifies it).

**Two frontends, one behaviour.** Desktops with a StatusNotifier/AppIndicator tray (MATE, XFCE, Cinnamon, KDE, Unity...) use the C binary `phcc` (GTK 3 + libayatana-appindicator). GNOME Shell has no tray by default, so the package also ships the native GNOME Shell extension `phcc@pymehackers.com` (ESM, GNOME 45 to 50), which avoids depending on `gnome-shell-extension-appindicator`. Both frontends implement the same menu, the same discovery and the same catalogue logic in two languages; every behaviour change must be mirrored in `frontend/indicator.c` and `frontend/gnome-extension/extension.js`.

**One icon, never two.** The autostart entry of the binary (`phcc.desktop`) has `NotShowIn=GNOME;`; the GNOME-only autostart (`phcc-gnome-activate.desktop`, `OnlyShowIn=GNOME;`) runs `phcc-show --quiet`, which enables the extension. The applications-menu launcher runs `phcc-show`, which looks at `XDG_CURRENT_DESKTOP`: on GNOME it enables the extension, elsewhere it starts `phcc` unless a process with that name already exists.

**Dynamic discovery through Desktop Entry manifests.** The code never names a module. Each module installs a `.desktop` manifest in `/usr/share/pymehackers/modules/<section>/` and the frontends read that registry when they build the menu. The Desktop Entry format was chosen because GLib's `GKeyFile` parses it natively from C and from GJS, it supports localised keys (`Name[es_AR]`) and it already defines Desktop Actions, which map one-to-one to the action submenu of a module. See [Module discovery contract](#module-discovery-contract).

**Least privilege.** Both frontends run as the session user. The only privileged code path is `phcc-modules install|update|reinstall|uninstall`, started through `pkexec`. The polkit policy pins the exact program path (`org.freedesktop.policykit.exec.path` = `/usr/libexec/phcc/phcc-modules`) and requires administrator authentication (`auth_admin`, `auth_admin_keep` for active sessions). Listing the catalogue never needs root. The repository owner, name and branch are constants in the helper, so no argument can point a root operation at another source.

**A line protocol between the helper and the frontends.** `phcc-modules list` prints one module per line with 7 TAB-separated fields. The frontends only split lines, which keeps the C code free of any JSON parser for the catalogue. All JSON handling of `module.json` stays in the bash helper (`jq`).

**Translations in JSON, with a small parser in C.** Every visible text lives in `frontend/lang/<language>.json`. GLib has no JSON parser and the files are flat objects, so `frontend/i18n.c` contains a strict parser for exactly that shape instead of adding a `json-glib` dependency; GJS uses `JSON.parse` and the shell scripts use `jq`. The only texts outside the JSON files are the `Name[xx]`/`Comment[xx]` keys of the `.desktop` files and the `xml:lang` texts of the polkit policy, because the desktop and polkit read those files directly (documented exception in `RulesForThisProjectOnly.md`).

**Asynchronous everything.** Catalogue listing and module operations run as `GSubprocess`/`Gio.Subprocess` children with asynchronous completion callbacks, so the panel never blocks. Each frontend process allows one module operation at a time (`vBusy`); this is a per-process flag, not a system-wide lock.

**Built on the target, from source.** No prebuilt binary is distributed: the one-line installer downloads the source tarball of `main` and compares its version with the installed one; only when something has to be built does it install the build dependencies, build the `.deb` with `build/native/build.sh` and install it with `apt-get install --allow-downgrades`, so the repository version always wins, even when it is older. The arm64 cross-build flow exists for developers who want to build arm64 packages on an amd64 host.

**No windows.** The core only shows menus and notifications, so the GNOME window rules of the project have nothing to apply to.

## Module map

| Module | Path | Responsibility | Depends on | Used by |
|---|---|---|---|---|
| AppIndicator | [`frontend/indicator.c`](../app-debian/frontend/indicator.c) | Top-bar icon and menu on AppIndicator desktops: sections, module actions, catalogue, notifications | GTK 3, libayatana-appindicator3, `i18n.c`, registry, `phcc-modules` | `phcc.desktop` autostart, `phcc-show` |
| Translations (C) | [`frontend/i18n.c`](../app-debian/frontend/i18n.c), [`frontend/i18n.h`](../app-debian/frontend/i18n.h) | Locale to language, strict flat-JSON loader, `fT`/`fTf` lookups with en-US fallback | GLib, `lang/*.json` | `indicator.c` |
| GNOME Shell extension | [`frontend/gnome-extension/extension.js`](../app-debian/frontend/gnome-extension/extension.js) | Panel button and menu on GNOME Shell with the same features as the AppIndicator | GNOME Shell 45 to 50 (St, PanelMenu, PopupMenu, Gio), `lang/*.json`, registry, `phcc-modules` | GNOME Shell, `phcc-show` |
| Extension metadata and style | [`frontend/gnome-extension/metadata.json`](../app-debian/frontend/gnome-extension/metadata.json), [`stylesheet.css`](../app-debian/frontend/gnome-extension/stylesheet.css) | UUID, supported Shell versions, placeholder stylesheet | none | GNOME Shell |
| Language files | [`frontend/lang/`](../app-debian/frontend/lang/) | All visible texts in en-GB, en-US, es-AR and es-ES | none | AppIndicator, extension, `phcc-show` |
| Desktop entries | [`frontend/desktop/`](../app-debian/frontend/desktop/) | Autostart of the binary, GNOME autostart, applications-menu launcher | `phcc`, `phcc-show` | Session autostart, applications menu |
| Icons | [`frontend/icons/`](../app-debian/frontend/icons/) | Colour SVG (`phcc`), symbolic SVG (`phcc-symbolic`), colour PNG 16 to 512 px | none | AppIndicator, extension, launchers, notifications, polkit dialog |
| Display wrapper | [`backend/phcc-show`](../app-debian/backend/phcc-show) | Shows the icon the right way for the desktop, idempotently | bash, `jq`, `gnome-extensions`, `pgrep`, `setsid`, `notify-send` | Launcher, GNOME autostart |
| Catalogue helper | [`backend/phcc-modules`](../app-debian/backend/phcc-modules) | Lists PHCC-modules and runs the Debian installer of a module | bash, `curl`, `jq`, `dpkg`, `dpkg-query`, GitHub | AppIndicator, extension, `pkexec` |
| Polkit policy | [`backend/polkit/com.pymehackers.phcc.modules.policy`](../app-debian/backend/polkit/com.pymehackers.phcc.modules.policy) | Authorises `pkexec` to run the helper as root | polkit | `pkexec` |
| Makefile | [`build/Makefile`](../app-debian/build/Makefile) | Compiles `out/phcc`; manual `install` target | `gcc`, `pkg-config`, -dev libraries | `build-deb.sh`, `arm64-cross/build.sh` |
| Packager | [`build/build-deb.sh`](../app-debian/build/build-deb.sh) | Stages and builds the `.deb` for the native architecture | Makefile, `build/debian/`, `dpkg-deb` | `native/build.sh` |
| Package metadata | [`build/debian/control`](../app-debian/build/debian/control), [`postinst`](../app-debian/build/debian/postinst), [`postrm`](../app-debian/build/debian/postrm) | Version, dependencies, post-install and post-removal steps | none | `build-deb.sh`, `arm64-cross/build.sh`, `dpkg` |
| Native build flow | [`build/native/`](../app-debian/build/native/) | Build dependencies, build, verification, collection in `dist/` | `build-deb.sh` | Installer, developers |
| arm64 cross-build flow | [`build/arm64-cross/`](../app-debian/build/arm64-cross/) | Multiarch toolchain, cross-compilation, packaging, verification | Makefile, `build/debian/`, `aarch64-linux-gnu-gcc` | Developers |
| Installer | [`build/install-update-reinstall-debian.sh`](../app-debian/build/install-update-reinstall-debian.sh) | One-line install, update, reinstall and uninstall as root | `apt-get`, `curl`, GitHub tarball, `native/build.sh` | Operators |
| Tests | [`tests/`](../app-debian/tests/) | Empty: the project rules forbid writing tests | none | none |

## Key symbol index

Only public or key symbols. Line numbers come from `grep -n` on the current tree.

| Symbol | File:line | What it does |
|---|---|---|
| `cModulesRoot` | `frontend/indicator.c:26` | Registry root `/usr/share/pymehackers/modules` |
| `cModulesHelper` | `frontend/indicator.c:30` | Helper path; must match the polkit `exec.path` |
| `aSections` | `frontend/indicator.c:42` | Section ids (`sys`, `cs`) and their label keys |
| `CatalogEntry` | `frontend/indicator.c:56` | One parsed line of `phcc-modules list` |
| `vCatalog` | `frontend/indicator.c:79` | Catalogue state (loading/ready/failed), entries and busy flag |
| `fNotify` | `frontend/indicator.c:86` | Desktop notification through `notify-send` (log only if missing) |
| `fOnActionActivate` | `frontend/indicator.c:113` | Runs the `Exec` of a module action without blocking |
| `fBuildModuleActions` | `frontend/indicator.c:129` | Builds the action submenu from `Actions` and `[Desktop Action ...]` |
| `fCompareModules` | `frontend/indicator.c:176` | Sorts modules by `X-PYMEHackers-Order`, then by name |
| `fBuildSectionMenu` | `frontend/indicator.c:188` | Reads one registry folder and fills a section submenu |
| `fParseCatalog` | `frontend/indicator.c:277` | Parses the 7-field lines of the helper |
| `fOnCatalogListed` | `frontend/indicator.c:304` | Stores the listed catalogue and rebuilds the menu |
| `fLoadCatalog` | `frontend/indicator.c:330` | Starts `phcc-modules list --lang X [--refresh]` asynchronously |
| `fOnOperationFinished` | `frontend/indicator.c:383` | Maps the exit status to a notification and reloads the catalogue |
| `fOnCatalogActionActivate` | `frontend/indicator.c:410` | Starts `pkexec phcc-modules <action> <id>` |
| `fBuildCatalogMenu` | `frontend/indicator.c:463` | Builds the "Module catalogue" submenu from the current state |
| `fBuildMenu` | `frontend/indicator.c:543` | Builds the whole root menu |
| `fRefreshMenu` | `frontend/indicator.c:580` | Rebuilds the menu and hands it to the indicator |
| `main` | `frontend/indicator.c:586` | Initialises GTK and translations, creates the indicator, loads the catalogue |
| `cDefaultLangDir` | `frontend/i18n.h:15` | `/usr/share/pymehackers/core/lang` (overridden by `PHCC_LANG_DIR`) |
| `aSupportedLanguages` | `frontend/i18n.c:14` | en-GB, en-US, es-AR, es-ES |
| `fParseObject` | `frontend/i18n.c:118` | Strict parser of a flat JSON object of strings |
| `fMatchLanguage` | `frontend/i18n.c:198` | Locale name to supported language |
| `fI18nInit` | `frontend/i18n.c:225` | Resolves the language and loads it plus the en-US fallback |
| `fI18nLanguage` | `frontend/i18n.c:247` | Selected language (passed to the helper as `--lang`) |
| `fT` | `frontend/i18n.c:251` | Text of a key (selected, then en-US, then the key itself) |
| `fTf` | `frontend/i18n.c:260` | `fT` with `{0}`, `{1}`... placeholders |
| `cModulesHelper` | `frontend/gnome-extension/extension.js:39` | Helper path used by the extension |
| `cUuid` | `frontend/gnome-extension/extension.js:46` | `phcc@pymehackers.com`, used by "Quit" |
| `fMatchLanguage` | `frontend/gnome-extension/extension.js:55` | Same language resolution as `i18n.c` |
| `Translator` | `frontend/gnome-extension/extension.js:83` | Loads the selected language and the en-US fallback; `mT` at line 98 |
| `PymeHackersIndicator` | `frontend/gnome-extension/extension.js:107` | `PanelMenu.Button` subclass; `_init` at line 110 |
| `mBuildMenu` | `frontend/gnome-extension/extension.js:141` | Header, sections, catalogue and "Quit" |
| `mDiscoverModules` | `frontend/gnome-extension/extension.js:194` | Reads one registry folder and sorts the modules |
| `mParseManifest` | `frontend/gnome-extension/extension.js:232` | Reads `Name`, `X-PYMEHackers-Order` and the actions of a manifest |
| `mLoadCatalog` | `frontend/gnome-extension/extension.js:280` | Runs `phcc-modules list` asynchronously |
| `mParseCatalog` | `frontend/gnome-extension/extension.js:319` | Parses the 7-field lines |
| `mBuildCatalog` | `frontend/gnome-extension/extension.js:347` | Fills the "Module catalogue" submenu |
| `mRunOperation` | `frontend/gnome-extension/extension.js:407` | Runs `pkexec phcc-modules <action> <id>` and notifies |
| `mQuit` | `frontend/gnome-extension/extension.js:461` | Hides the icon with `gnome-extensions disable` |
| `PymeHackersExtension.enable` / `disable` | `frontend/gnome-extension/extension.js:472` / `478` | Adds or destroys the panel indicator |
| `fIsGnome` | `backend/phcc-show:106` | `XDG_CURRENT_DESKTOP` contains `GNOME` |
| `fEnableOnGnome` | `backend/phcc-show:114` | Waits for the Shell to know the extension, then enables it |
| `fLaunchBinary` | `backend/phcc-show:160` | Starts `phcc` with `setsid -f` unless `pgrep -u <uid> -x phcc` finds one of the same user |
| `fMain` | `backend/phcc-show:178` | Parses `--quiet`/`--help` and picks the path |
| `cApiUrl`, `cRawUrl`, `cInstallerPath` | `backend/phcc-modules:31`, `32`, `33` | Fixed repository URLs and installer path |
| `cLogFile` | `backend/phcc-modules:34` | `/var/log/phcc-modules.log` |
| `cIdPattern`, `cPackagePattern` | `backend/phcc-modules:36`, `37` | Validation of module ids and package names |
| `fLog` | `backend/phcc-modules:62` | stderr and, as root, the log with a UTC timestamp |
| `fNormalizeLanguage` | `backend/phcc-modules:71` | Locale or tag to supported language |
| `fPlatform` | `backend/phcc-modules:111` | `debian-$(dpkg --print-architecture)` |
| `fInstalledVersion` | `backend/phcc-modules:120` | Installed version of a package (status `ii` only) |
| `fDownloadCatalog` | `backend/phcc-modules:131` | GitHub listing, `module.json` download and validation |
| `fCatalogFile` | `backend/phcc-modules:188` | Per-user 10-minute cache; root always downloads |
| `fList` | `backend/phcc-modules:229` | `list` command: prints the 7-field lines |
| `fRunOperation` | `backend/phcc-modules:267` | Root operation: checks, downloads and runs the module installer |
| `fMain` | `backend/phcc-modules:344` | Command-line parsing |
| `com.pymehackers.phcc.modules` | `backend/polkit/com.pymehackers.phcc.modules.policy:16` | Polkit action; `exec.path` at line 32 |
| `all`, `install`, `clean` | `build/Makefile:46`, `52`, `69` | Make targets |
| `fMain` | `build/build-deb.sh:27` | Native `.deb` packager |
| `fVerify` | `build/native/build.sh:123` | Mandatory paths and "core without modules" guard |
| `fCollectArtifact` | `build/native/build.sh:216` | Atomic copy into `native/dist/` |
| `fCompile` | `build/arm64-cross/build.sh:115` | Cross-compiles and checks the ELF architecture |
| `fPackage` | `build/arm64-cross/build.sh:137` | Stages and builds the arm64 `.deb` |
| `fVerify` | `build/arm64-cross/build.sh:280` | Same guard as the native flow |
| `fStartLog` | `build/install-update-reinstall-debian.sh:50` | Tees all output to `/root/phcc-install.log` (mode 600) |
| `fDownloadSource` | `build/install-update-reinstall-debian.sh:116` | Downloads and extracts the `main` tarball |
| `fBuildAndInstall` | `build/install-update-reinstall-debian.sh:143` | Version check, build dependencies (only when building), build, `apt-get install -y --allow-downgrades` |
| `fUninstall` | `build/install-update-reinstall-debian.sh:89` | `apt-get remove phcc` |
| `fMain` | `build/debian/postinst:11` | Registry folders, log file, desktop and icon caches |
| `fMain` | `build/debian/postrm:11` | On `purge`: empty registry folders and the log |

## Main call paths

### Session start on AppIndicator desktops

```text
/etc/xdg/autostart/phcc.desktop (Exec=phcc, NotShowIn=GNOME)
  └─ main                                  indicator.c:586
      ├─ gtk_init, fI18nInit
      ├─ g_object_new(APP_INDICATOR_TYPE, id=phcc, icon-name=phcc)
      └─ fLoadCatalog(FALSE)
          ├─ g_subprocess_new(phcc-modules list --lang <language>)
          ├─ fRefreshMenu ─ fBuildMenu ─┬─ fBuildSectionMenu(sys), fBuildSectionMenu(cs)
          │                             └─ fBuildCatalogMenu   (key catalog.loading)
          └─ (async) fOnCatalogListed ─ fParseCatalog ─ fRefreshMenu
```

### Session start on GNOME Shell

```text
/etc/xdg/autostart/phcc-gnome-activate.desktop (Exec=phcc-show --quiet, OnlyShowIn=GNOME)
  └─ phcc-show fMain ─ fIsGnome ─ fEnableOnGnome
      ├─ gnome-extensions info phcc@pymehackers.com   (up to 10 attempts, 1 s apart)
      ├─ gnome-extensions list --enabled              (already enabled: done)
      └─ gnome-extensions enable phcc@pymehackers.com
GNOME Shell ─ PymeHackersExtension.enable ─ new PymeHackersIndicator
  └─ _init ─ Translator ─ mBuildMenu ─ mLoadCatalog(false)
      └─ (async) mParseCatalog ─ mRebuildMenu
```

### Applications-menu launcher

```text
pymehackers-control-center.desktop (Exec=phcc-show)
  └─ phcc-show fMain
      ├─ GNOME:  fEnableOnGnome (1 attempt, notifications on)
      └─ other:  fLaunchBinary ─ pgrep -u $(id -u) -x phcc ─ setsid -f phcc
```

### Module action

```text
menu item ─ fOnActionActivate (C) | mSpawn (JS)
  └─ g_spawn_command_line_async(<Exec of the Desktop Action>)   (session user, no shell)
```

### Catalogue operation (install, update, reinstall, uninstall)

```text
menu item ─ fOnCatalogActionActivate (C) | mRunOperation (JS)
  ├─ notification "notify.<action>"
  └─ pkexec /usr/libexec/phcc/phcc-modules <action> <id>
      └─ polkit action com.pymehackers.phcc.modules (auth_admin_keep)
          └─ fMain ─ fRunOperation
              ├─ fPlatform, fCatalogFile(1) ─ fDownloadCatalog (fresh, no cache)
              ├─ jq: module present and platform supported
              ├─ curl <raw>/<id>/app-debian/build/install-update-reinstall-debian.sh
              ├─ first two bytes must be "#!"
              └─ bash installer [--reinstall|--uninstall] < /dev/null >> /var/log/phcc-modules.log
  (async) fOnOperationFinished (C) | wait_async callback (JS)
      ├─ exit 0: notify.done, 126: notify.cancelled, 127: notify.denied, other: notify.failed
      └─ fLoadCatalog(TRUE) | mLoadCatalog(true) ─ menu rebuilt (sections rediscovered)
```

### Catalogue listing inside the helper

```text
phcc-modules list [--lang L] [--refresh]
  └─ fMain ─ fNormalizeLanguage | fSessionLanguage ─ fList
      ├─ fPlatform
      ├─ fCatalogFile(refresh)
      │   ├─ cache hit (< 600 s): ~/.cache/phcc/catalog.json
      │   └─ fDownloadCatalog: GitHub contents API ─ per folder module.json ─ jq validation ─ jq -s
      └─ jq projection ─ fInstalledVersion(package) ─ printf 7 TAB-separated fields
```

### One-line install

```text
curl ... | bash
  └─ fMain ─ fCheckSystem ─ fStartLog
      ─ fDownloadSource (codeload tarball of main) ─ fBuildAndInstall
          ├─ fRepositoryVersion vs fInstalledVersion (equal and no --reinstall: stop)
          ├─ fInstallDependencies (apt-get update/install, only when something is built)
          ├─ native/build.sh ─ fCheckDependencies ─ fBuildAndPackage
          │   └─ build-deb.sh ─ make all ─ staging ─ dpkg-deb --root-owner-group --build
          │   ─ fVerify ─ fCollectArtifact (native/dist/)
          └─ apt-get install -y --allow-downgrades [--reinstall] native/dist/phcc_<version>_<arch>.deb ─ postinst
```

### arm64 cross-build

```text
arm64-cross/build.sh ─ fCheckEnvironment ─ fCheckDependencies ─ fReadVersion
  ─ fCompile (make -C build all CC=aarch64-linux-gnu-gcc BUILDDIR=out-arm64, file -b = aarch64)
  ─ fPackage (staging, control Architecture amd64 to arm64, dpkg-deb)
  ─ fVerify ─ fCollectArtifact (arm64-cross/dist/)
```

## Entry and command map

### Programs, desktop entries and extension

| Route/command | Handler | File |
|---|---|---|
| `phcc` | `main` | `frontend/indicator.c` |
| `phcc-show` | `fMain` (manual mode, notifications) | `backend/phcc-show` |
| `phcc-show --quiet` | `fMain` (no notifications, 10 attempts) | `backend/phcc-show` |
| `phcc-show --help` | `fMain` (prints `Usage: phcc-show [--quiet]`) | `backend/phcc-show` |
| `/usr/libexec/phcc/phcc-modules list [--lang LANG] [--refresh]` | `fList` | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules install ID` / `update ID` | `fRunOperation` (installer without arguments) | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules reinstall ID` | `fRunOperation` (`--reinstall`) | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules uninstall ID` | `fRunOperation` (`--uninstall`) | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules -h` / `--help` | `fShowUsage` | `backend/phcc-modules` |
| `pkexec /usr/libexec/phcc/phcc-modules ...` | polkit action `com.pymehackers.phcc.modules` | `backend/polkit/com.pymehackers.phcc.modules.policy` |
| `/etc/xdg/autostart/phcc.desktop` | `Exec=phcc`, `NotShowIn=GNOME;`, MATE delay 3 s | `frontend/desktop/phcc.desktop` |
| `/etc/xdg/autostart/phcc-gnome-activate.desktop` | `Exec=phcc-show --quiet`, `OnlyShowIn=GNOME;`, delay 5 s | `frontend/desktop/phcc-gnome-activate.desktop` |
| `/usr/share/applications/pymehackers-control-center.desktop` | `Exec=phcc-show` | `frontend/desktop/pymehackers-control-center.desktop` |
| GNOME extension `phcc@pymehackers.com` | `PymeHackersExtension.enable` / `disable` | `frontend/gnome-extension/extension.js` |

Exit codes of the helper: `0` success, `1` any failure. Usage errors return `2` inside `fMain`, but the mandatory `if ! fMain` wrapper turns every failure into `1`. `pkexec` itself returns `126` (dialog dismissed) or `127` (not authorised, no authentication agent or error); the frontends show "notify.cancelled" for `126` and "notify.denied" for `127`.

Environment variables read by the code: `PHCC_LANG_DIR` (only the C indicator), `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG` (language, all components), `XDG_CURRENT_DESKTOP` (`phcc-show`), `XDG_CACHE_HOME` and `HOME` (helper cache), `DESTDIR` and `PREFIX` (Makefile).

### Build and installation scripts

| Route/command | Handler | File |
|---|---|---|
| `make -C app-debian/build` (`all`) | builds `out/phcc` | `build/Makefile` |
| `make -C app-debian/build all CC=... BUILDDIR=...` | overrides used by the arm64 flow | `build/Makefile` |
| `make -C app-debian/build install [DESTDIR=...] [PREFIX=/usr]` | copies the files, no maintainer scripts | `build/Makefile` |
| `make -C app-debian/build clean` | removes `out/` | `build/Makefile` |
| `app-debian/build/build-deb.sh` | `fMain`, writes `out/phcc_<version>_<arch>.deb` | `build/build-deb.sh` |
| `app-debian/build/native/build.sh [--clean] [--install-deps] [--help]` | `fMain`, writes `native/dist/` | `build/native/build.sh` |
| `app-debian/build/native/install-build-dependencies.sh` | `fMain` | `build/native/install-build-dependencies.sh` |
| `app-debian/build/arm64-cross/build.sh [--install-deps] [--clean] [--help]` | `fMain`, writes `arm64-cross/dist/` | `build/arm64-cross/build.sh` |
| `app-debian/build/arm64-cross/install-build-dependencies.sh` | `fMain` | `build/arm64-cross/install-build-dependencies.sh` |
| `install-update-reinstall-debian.sh` | install or update | `build/install-update-reinstall-debian.sh` |
| `install-update-reinstall-debian.sh --reinstall` | build and reinstall the same version | `build/install-update-reinstall-debian.sh` |
| `install-update-reinstall-debian.sh --uninstall` | `apt-get remove phcc` | `build/install-update-reinstall-debian.sh` |
| `install-update-reinstall-debian.sh --help` | `fShowHelp` | `build/install-update-reinstall-debian.sh` |
| `postinst` (any argument) | `fMain` | `build/debian/postinst` |
| `postrm purge` | `fMain` (cleanup only on `purge`) | `build/debian/postrm` |

## Module discovery contract

This is what a module must do on Debian to appear under "Systems" or "Cybersecurity". Both frontends implement it (`fBuildSectionMenu`/`fBuildModuleActions` in C, `mDiscoverModules`/`mParseManifest` in JS).

- **Location.** A file ending in `.desktop` inside `/usr/share/pymehackers/modules/sys/` or `/usr/share/pymehackers/modules/cs/`. The folder decides the section; any `X-PYMEHackers-Section` key is ignored by the core.
- **`[Desktop Entry]` `Name`** (mandatory). Visible label of the module. Localised keys (`Name[es_AR]`, `Name[es]`...) are honoured through GLib's locale rules. A manifest without `Name`, or that `GKeyFile` cannot parse, is skipped.
- **`X-PYMEHackers-Order`** (optional integer). Lower values appear first; missing or invalid means `1000`. Ties are sorted by name (byte order in C, `localeCompare` in JS).
- **`Actions`** (optional). Semicolon-separated action ids. Each id needs a `[Desktop Action <id>]` group with `Name` (localisable) and `Exec`; an action missing either key is skipped. A module without an `Actions` key is shown as a plain item, without submenu; the GNOME extension also does so when none of its actions is valid.
- **`Exec`.** Run as the session user with `g_spawn_command_line_async` (C) or `GLib.spawn_command_line_async` (JS): quoting follows shell rules but there is no shell, so pipes, redirections, variables and field codes such as `%f` do not work. An action that needs root must call `pkexec` itself.
- **Ignored keys.** `Icon`, `Comment`, `X-PYMEHackers-Section`, `X-PYMEHackers-Service` and any other key may exist for the module's own use; the core does not read them.
- **Refresh.** There is no file watcher. The menu is rebuilt at start-up and after every catalogue listing (start-up, "Refresh catalogue", end of a catalogue operation). A manifest installed from a terminal shows up after "Refresh catalogue" or a restart of the frontend.

Example manifest (`/usr/share/pymehackers/modules/cs/example.desktop`):

```ini
[Desktop Entry]
Type=Application
Name=Example
Name[es_AR]=Ejemplo
Name[es_ES]=Ejemplo
X-PYMEHackers-Order=10
Actions=Configure;Monitor;

[Desktop Action Configure]
Name=Configure
Name[es]=Configurar
Exec=pkexec /usr/bin/phcc-mod-example-manager

[Desktop Action Monitor]
Name=View events
Name[es]=Ver eventos
Exec=/usr/bin/phcc-mod-example-monitor
```

## Module catalogue contract

The contract is shared with PHCC-modules and recorded in `RulesForThisProjectOnly.md` of both projects. The Debian side is implemented by `backend/phcc-modules`.

**Repository.** `https://github.com/pymehackers/PHCC-modules`, branch `main` (`backend/phcc-modules:28-33`). It cannot be changed at run time on purpose.

**What is a module.** Any top-level folder, listed through `https://api.github.com/repos/pymehackers/PHCC-modules/contents?ref=main` with `type == "dir"`, whose name matches `^[a-z0-9][a-z0-9-]{0,62}$` and whose `module.json` can be downloaded from `https://raw.githubusercontent.com/pymehackers/PHCC-modules/main/<id>/module.json`. Folders without `module.json` (for example `_` or `doc`) are skipped silently; an invalid `module.json` is skipped and logged as `ignoring <id>: its module.json is not valid`.

**`module.json` as validated on Debian (`jq`).**

| Field | Rule in the helper | Use |
|---|---|---|
| `id` | must equal the folder name | Operation argument |
| `section` | `sys` or `cs` | Sorting (Systems first) |
| `version` | string | Shown; compared with the installed version |
| `package` | string matching `^[a-z0-9][a-z0-9+.-]+$` | `dpkg-query` lookup of the installed version |
| `name`, `description` | objects keyed `en-GB`, `en-US`, `es-AR`, `es-ES` | Selected language, then `en-US`, then the id (name) or empty (description) |
| `platforms` | array or absent | `debian-amd64` / `debian-arm64` must be present to be supported; absent means supported nowhere |

```json
{
  "id": "example",
  "section": "cs",
  "version": "1.2.0",
  "package": "phcc-mod-example",
  "name": {"en-GB": "Example", "en-US": "Example", "es-AR": "Ejemplo", "es-ES": "Ejemplo"},
  "description": {"en-GB": "...", "en-US": "...", "es-AR": "...", "es-ES": "..."},
  "platforms": ["debian-amd64", "debian-arm64"]
}
```

**Platform id.** `debian-` followed by `dpkg --print-architecture` (`debian-amd64` and `debian-arm64`; any other architecture is never listed in `platforms` today, so every module shows as unsupported there).

**Installed version.** `dpkg-query -W -f='${db:Status-Abbrev}|${Version}' <package>`; only status `ii` counts as installed.

**Output of `list`.** One line per valid module, 7 TAB-separated fields: `id`, `section`, `version`, installed version (empty when not installed), supported (`0`/`1`), name, description. TAB, CR, LF and `0x1F` inside the texts are replaced by spaces. The frontends sort Systems before Cybersecurity, then by name, and ignore lines without 7 fields, without id or without name.

**Operations.** `install` and `update` run the installer without arguments, `reinstall` adds `--reinstall`, `uninstall` adds `--uninstall`. The helper refuses to run unless it is root, the id is valid, the module is in a freshly downloaded catalogue and its `platforms` lists the current platform. The installer is `<id>/app-debian/build/install-update-reinstall-debian.sh`, downloaded from `raw.githubusercontent.com`; its first two bytes must be `#!`. It runs as `bash <installer> [argument] < /dev/null >> /var/log/phcc-modules.log 2>&1`, so it must be idempotent and non-interactive, must exit `0` on success, must install the module manifest into the registry, and must remove it on `--uninstall`.

**Update detection.** The frontends offer "Update to <version>" when the installed version string differs from the catalogue version. It is a string comparison, not dpkg version ordering.

**Cache.** `${XDG_CACHE_HOME:-$HOME/.cache}/phcc/catalog.json` per user, valid for 600 seconds; `--refresh` ("Refresh catalogue") skips it. Root never uses a cache.

**Network.** `curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 --retry 2`. The GitHub API is used without authentication (GitHub allows 60 requests per hour and IP address); each catalogue download costs one API request plus one raw download per folder.

**Log.** `/var/log/phcc-modules.log`, mode `0640`, created by `postinst` or by the first operation. `fLog` writes lines only when it runs as root, with the native UTC timestamp, for example `2026-10-29@13-59-59.723 install example: started`. The output of the module installer is appended as is, without timestamps.

**Trust model.** Integrity relies on HTTPS to GitHub, the fixed repository and polkit authentication. There are no signatures: whoever can push to `main` of PHCC-modules can run code as root on every machine where an administrator authorises an operation.

## Language files

- Source: `frontend/lang/{en-GB,en-US,es-AR,es-ES}.json`. Installed: `/usr/share/pymehackers/core/lang/`. Flat JSON objects of string keys and string values; `{0}`, `{1}`... are placeholders.
- Lookup: selected language, then `en-US`, then the key itself (a missing key shows up as its name).
- Language resolution (identical in `i18n.c:198`, `extension.js:55`, `phcc-show:35` and `phcc-modules:71`): the first entry of `LANGUAGE` (colon list), `LC_ALL`, `LC_MESSAGES`, `LANG` that matches. Codeset and modifier are dropped (`es_AR.UTF-8` becomes `es-AR`); an exact match wins; otherwise `en`/`en-*` maps to `en-US` and `es`/`es-*` to `es-ES`; anything else (`C`, `fr_FR`...) gives `en-US`. The C and JS frontends use `g_get_language_names()`, which follows the same variables.

| Keys | Used by |
|---|---|
| `app.title` | Indicator title and notifications (C), menu header and notifications (JS), `phcc-show` notifications |
| `menu.header` | Menu header of the AppIndicator only |
| `menu.catalog`, `menu.quit`, `section.*` | Both frontends |
| `catalog.*`, `action.*`, `notify.*` (including `notify.denied`), `error.spawn` | Both frontends |
| `error.registry`, `error.quit` | GNOME extension only |
| `show.*` | `phcc-show` |

Texts that do not come from these files: module names and actions (module manifest), catalogue names and descriptions (`module.json`), the `.desktop` launchers and the polkit dialog (translated inside those files).

## Build and packaging

- **Compiler flags** (`build/Makefile`): `-std=c11 -O2 -Wall -Wextra -D_GNU_SOURCE` plus `pkg-config --cflags/--libs gtk+-3.0 ayatana-appindicator3-0.1`. Recipes use `.RECIPEPREFIX := >` so the Makefile contains no tabs (project indentation rule).
- **`build-deb.sh`**: reads `Version` from `build/debian/control` and the architecture from `dpkg --print-architecture`, runs `make all`, stages the tree in a `mktemp -d` folder with explicit modes, rewrites `Architecture`, checks the mandatory pieces, builds with `dpkg-deb --root-owner-group --build` into a temporary folder inside `out/`, checks `Package`, `Version` and `Architecture`, and moves the result to `out/phcc_<version>_<arch>.deb`.
- **`native/build.sh`**: checks `gtk+-3.0`, `ayatana-appindicator3-0.1`, `gcc`, `make`, `dpkg-deb`, `pkg-config`; runs `build-deb.sh`; `fVerify` lists the package (`dpkg-deb --info`, `--contents`), requires every mandatory path and applies the **"core without modules" guard**: it fails if the package contains anything matching `./usr/share/pymehackers/modules/(sys|cs)/.+`, `phcc-mod-` or `./etc/pymehackers/`. The verified `.deb` is copied into `native/dist/` atomically (temporary file, `cmp`, `chmod 0644`, `mv`).
- **`arm64-cross/build.sh`**: uses multiarch (`dpkg --add-architecture arm64`), `PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig` and `PKG_CONFIG_SYSROOT_DIR=/`, compiles into `build/out-arm64/`, requires `file -b` to report `aarch64` (its dependency script installs and checks `file`), stages its own package tree (a copy of the `build-deb.sh` logic), rewrites `Architecture: amd64` to `arm64`, applies the same guard and collects into `arm64-cross/dist/`. If a third-party apt source does not serve arm64, `apt-get update` fails: restrict that source with `Architectures: amd64`.
- **Dependency scripts** install with `apt-get` as root, or through `sudo` when run by another user; they read from `/dev/tty`, so they need a terminal. They do nothing when `pkg-config` already finds the libraries.
- **Script template**: every bash script uses `set -euo pipefail`, `fCleanup` + `trap fCleanup EXIT` and `if ! fMain`. Because Bash ignores `set -e` inside the operand of `!`, every critical step is checked explicitly.
- **Artefacts** (`out/`, `out-arm64/`, `native/dist/`, `arm64-cross/dist/`) are ignored by `.gitignore`.
- **Network or FUSE filesystems** (sshfs): `install -m` cannot always set modes there; build from a copy on a local disk.

## Files installed on the target system

Installed by the `phcc` package (owner `root:root`, `dpkg-deb --root-owner-group`):

| Path | Mode | Source |
|---|---|---|
| `/usr/bin/phcc` | 0755 | `build/out/phcc` (or `out-arm64/phcc`) |
| `/usr/bin/phcc-show` | 0755 | `backend/phcc-show` |
| `/usr/libexec/phcc/phcc-modules` | 0755 | `backend/phcc-modules` |
| `/usr/share/polkit-1/actions/com.pymehackers.phcc.modules.policy` | 0644 | `backend/polkit/` |
| `/etc/xdg/autostart/phcc.desktop` | 0644 | `frontend/desktop/` |
| `/etc/xdg/autostart/phcc-gnome-activate.desktop` | 0644 | `frontend/desktop/` |
| `/usr/share/applications/pymehackers-control-center.desktop` | 0644 | `frontend/desktop/` |
| `/usr/share/gnome-shell/extensions/phcc@pymehackers.com/metadata.json` | 0644 | `frontend/gnome-extension/` |
| `/usr/share/gnome-shell/extensions/phcc@pymehackers.com/extension.js` | 0644 | `frontend/gnome-extension/` |
| `/usr/share/gnome-shell/extensions/phcc@pymehackers.com/stylesheet.css` | 0644 | `frontend/gnome-extension/` |
| `/usr/share/pymehackers/core/lang/{en-GB,en-US,es-AR,es-ES}.json` | 0644 | `frontend/lang/` |
| `/usr/share/icons/hicolor/scalable/apps/phcc.svg` | 0644 | `frontend/icons/phcc.svg` |
| `/usr/share/icons/hicolor/symbolic/apps/phcc-symbolic.svg` | 0644 | `frontend/icons/phcc-symbolic.svg` |
| `/usr/share/icons/hicolor/<N>x<N>/apps/phcc.png` (N = 16, 22, 24, 32, 48, 64, 128, 256, 512) | 0644 | `frontend/icons/phcc-<N>.png` |
| `/usr/share/pymehackers/modules/sys/`, `/usr/share/pymehackers/modules/cs/` | 0755 (empty folders) | created by the packager |
| `DEBIAN/control` | 0644 | `build/debian/control` (Architecture rewritten) |
| `DEBIAN/postinst`, `DEBIAN/postrm` | 0755 | `build/debian/` |

The package declares no `conffiles`, so local edits to the files in `/etc/xdg/autostart/` are overwritten on upgrade (per-user overrides in `~/.config/autostart/` are not).

Created outside the package:

| Path | Mode | Created by |
|---|---|---|
| `/var/log/phcc-modules.log` | 0640 | `postinst`, or the first helper operation; removed on `purge` |
| `/root/phcc-install.log` | 0600 | `install-update-reinstall-debian.sh` (appended on every run) |
| `${XDG_CACHE_HOME:-~/.cache}/phcc/catalog.json` | user default | `phcc-modules list` run by each user |
| Temporary folders from `mktemp -d` | user default | helper and scripts; removed by `fCleanup` |

## Change-impact analysis

| If you change... | Also update |
|---|---|
| Registry path (`cModulesRoot`) | `indicator.c:26`, `extension.js:31`, `Makefile` `install`, `build-deb.sh`, `arm64-cross/build.sh`, verification patterns in `native/build.sh` and `arm64-cross/build.sh`, `postinst`, `postrm`, every module installer in PHCC-modules, the contract in `RulesForThisProjectOnly.md` |
| Helper path (`cModulesHelper`) | `indicator.c:30`, `extension.js:39`, polkit `exec.path`, `Makefile`, both packagers, both verification lists |
| Output format of `phcc-modules list` | `fParseCatalog`, `mParseCatalog` |
| `module.json` rules or installer path | `fDownloadCatalog`, `fList`, `fRunOperation`, `RulesForThisProjectOnly.md` of PHCC and PHCC-modules, every module |
| Section ids | `aSections` in C and JS, `section.*` keys, helper validation (`sys`/`cs`), registry folders in packagers, `postinst`, `postrm`, verification patterns |
| A visible text | The four `frontend/lang/*.json` files (a key missing from one language falls back to en-US) |
| Supported languages | `aSupportedLanguages` (`i18n.c`, `extension.js`), `aLanguages` (`phcc-show`, `phcc-modules`), `LANGS` (`Makefile`), language loops in both packagers and both verification lists, `.desktop` and polkit translations, `module.json` contract |
| Packaged file list | `Makefile` `install`, `build-deb.sh`, `arm64-cross/build.sh` `fPackage`, `fVerify` in both flows, [Files installed on the target system](#files-installed-on-the-target-system) |
| Package version | `Version` in `build/debian/control` only (the installer and both flows read it) |
| Extension UUID | `metadata.json`, `cUuid` in `extension.js` and `phcc-show`, `EXTUUID` in `Makefile`, both packagers and verification lists, `phcc.desktop` comment |
| Supported GNOME Shell versions | `shell-version` in `metadata.json` (test first: the extension uses the 45+ ESM API) |
| Runtime dependencies | `Depends`/`Recommends` in `build/debian/control`; build dependencies in `aBuildPackages` (installer) and `cAptPackages` (dependency scripts) |
| Polkit action or defaults | Policy file only (`pkexec` selects the action by `exec.path`) |

## Extension points

- **Add a module.** Nothing changes in the core: create the module in PHCC-modules with `module.json`, the Debian installer and the manifest described in [Module discovery contract](#module-discovery-contract).
- **Add an action to a module.** Edit the module manifest only (`Actions` plus one `[Desktop Action ...]` group).
- **Add a visible text.** Add the key to the four `frontend/lang/*.json` files and read it with `fT`/`fTf` (C), `this.mT` (JS) or `fT` (`phcc-show`).
- **Add a language.** Add `frontend/lang/<xx-YY>.json` and update every place listed under "Supported languages" in [Change-impact analysis](#change-impact-analysis).
- **Add a section.** Add it to `aSections` (C and JS), add `section.<id>` to every language file, accept it in the helper, create the registry folder in the packagers, `postinst` and `postrm`, extend the verification patterns, and update the contract in both projects.
- **Add a catalogue operation.** Add the case in `fRunOperation` and `fMain` of the helper, the menu item in `fBuildCatalogMenu` and `mBuildCatalog`, the `action.<name>` and `notify.<name>` keys and the installer argument in the PHCC-modules contract.
- **Add an architecture** (for example `armhf`). A new cross flow like `build/arm64-cross/`, and a new `debian-<arch>` platform id in the `module.json` contract.
- **Run the indicator from the source tree.** `make -C app-debian/build && PHCC_LANG_DIR=app-debian/frontend/lang app-debian/build/out/phcc`. The catalogue still needs the helper installed at `/usr/libexec/phcc/phcc-modules`, and the extension always reads `/usr/share/pymehackers/core/lang/`.

## Known limitations

- The menu does not watch the registry: a module installed outside the catalogue appears after "Refresh catalogue" or a restart.
- `vBusy` only serialises operations inside one frontend process; two users or a terminal can run the helper concurrently (apt's own lock still serialises package operations).
- `uninstall` through the catalogue needs the module to still be in the repository and to list the current platform; otherwise use the module's own installer with `--uninstall`.
- Installers and `module.json` are not signed (see the trust model above).
- The extension requires GNOME Shell 45 or later. Desktops whose `XDG_CURRENT_DESKTOP` contains `GNOME` without running GNOME Shell (for example Budgie or GNOME Flashback) get neither the extension nor the AppIndicator autostart.
- `/var/log/phcc-modules.log` is readable only by root, although the failure notification points the user to it.
- The menu header differs between frontends: `menu.header` ("PYMEHackers") in the AppIndicator, `app.title` ("PYMEHackers Control Center") in the extension.

## Repository layout

All product documentation lives in `doc/`. `app-debian/` contains `frontend/`, `backend/`, `build/` and `tests/`; `app-macos/` and `app-windows/` reserve the same structure. The root `README.md` only links to this documentation. Project rules and work tracking keep their required locations.


Notes on the pending platforms: [macOS](macos/CODE.en-GB.md), [Windows](windows/CODE.en-GB.md).
