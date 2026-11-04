# PYMEHackers Control Center: user manual

This MANUAL is also available in:\
en-GB, [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md)

This manual explains how to install, use and maintain PHCC, the PYMEHackers desktop application. The available implementation is Debian (package `phcc`), with Systems, Cybersecurity and the [PHCC-modules](https://github.com/pymehackers/PHCC-modules) catalog. See the [technical reference](CODE.en-GB.md). macOS and Windows are not implemented yet.

## Index

1. [Requirements](#requirements)
2. [Install](#install)
3. [First use](#first-use)
4. [The menu](#the-menu)
5. [Module catalogue](#module-catalogue)
6. [Languages](#languages)
7. [Logs](#logs)
8. [Command-line use](#command-line-use)
9. [Upgrade, reinstall and uninstall](#upgrade-reinstall-and-uninstall)
10. [Troubleshooting](#troubleshooting)

## Requirements

- Debian (or a derivative with `apt-get` and `dpkg`) on amd64 or arm64. The core is developed against Debian 13 (trixie).
- A graphical desktop:
  - **GNOME Shell 45 to 50**: the icon comes from the native extension `phcc@pymehackers.com`. Older GNOME versions (for example the GNOME 43 of Debian 12) cannot load it.
  - **MATE, XFCE, Cinnamon, KDE Plasma, Unity and other desktops with a system tray**: the icon comes from the `phcc` program (AppIndicator). The panel must have a notification area or status notifier applet.
- A polkit authentication agent running in the session (GNOME, KDE and Cinnamon include one; on MATE and XFCE it is usually `mate-polkit` or `polkit-gnome`). Without it, catalogue operations cannot ask for the password.
- Internet access to `github.com`, `api.github.com`, `raw.githubusercontent.com` and `codeload.github.com`.
- Root access for the installation (`su -` or a root console; `sudo` is not needed).

## Install

### One-line installer

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash
```

If `curl` is missing, install it first with `apt-get install -y curl`.

The installer:

1. Downloads the source of the `main` branch of [PHCC](https://github.com/pymehackers/PHCC) and compares its version with the installed one.
2. Only when something has to be built, updates the apt indexes and installs the build tools (`build-essential`, `pkg-config`, `libgtk-3-dev`, `libayatana-appindicator3-dev`, `dpkg-dev`, `file`, `curl`, `ca-certificates`).
3. Builds the `phcc` package for the architecture of the machine, checks its content and installs it with `apt-get`, which also installs the runtime dependencies (`curl`, `jq`, `pkexec`, the GTK and AppIndicator libraries and, as a recommendation, `libnotify-bin` for notifications).
4. Writes everything it does to `/root/phcc-install.log` (mode 600).

Running it again is safe: when the installed version is already the one in the repository, it says so and stops before installing anything.

### Build from source

On a Debian machine with the source tree (for example a clone of the repository):

```bash
app-debian/build/native/build.sh --install-deps
```

The verified package is left in `app-debian/build/native/dist/phcc_<version>_<arch>.deb`. Install it as root:

```bash
apt-get install -y ./app-debian/build/native/dist/phcc_0.0.2_amd64.deb
```

Options of `native/build.sh`: `--clean` removes previous build results first, `--install-deps` installs the build dependencies first (as root, or through `sudo` when run by another user), `--help` shows the help.

To build the arm64 package on an amd64 machine, use the cross-build flow:

```bash
app-debian/build/arm64-cross/build.sh --install-deps
```

It enables the arm64 architecture in dpkg (multiarch), installs the cross compiler and the arm64 libraries, and leaves `app-debian/build/arm64-cross/dist/phcc_<version>_arm64.deb`. If `apt-get update` fails because a third-party source does not offer arm64, add `Architectures: amd64` to that source in `/etc/apt/sources.list.d/` and try again.

If the source tree is on a network or FUSE filesystem (sshfs), build from a copy on a local disk. Use `--clean` whenever the same tree has been built on another architecture, so an old binary is never packaged.

## First use

- **GNOME Shell**: log out and log back in after the first installation, so the Shell registers the new extension. At every login, the autostart entry "PYMEHackers Control Center (enable the GNOME icon)" enables the extension automatically.
- **Other desktops**: the `phcc` program starts at every login (on MATE with a 3-second delay). After the first installation you can start it at once from the applications menu.
- **Any desktop**: the applications-menu entry "PYMEHackers Control Center" shows the icon. Opening it again never duplicates the icon; it tells you "The icon is already in the top bar." or "The indicator is already running.". On GNOME, if the Shell does not know the extension yet, it says "Log out and log back in to finish enabling the icon.".

## The menu

Click the PYMEHackers Control Center icon in the top bar. The menu contains:

| Item | What it does |
|---|---|
| "PYMEHackers" (AppIndicator) or "PYMEHackers Control Center" (GNOME) | Title, not clickable |
| "Systems" | Installed Systems modules; each module opens a submenu with its actions |
| "Cybersecurity" | Installed Cybersecurity modules, with their actions |
| "Module catalogue" | Modules published in PHCC-modules (see [Module catalogue](#module-catalogue)) |
| "Quit" | Hides the icon |

A section without modules shows "(no modules installed)". The names of the modules and of their actions (for example "Configure" or "View detections") come from each module and run with your user; actions that need root ask for the password themselves.

"Quit" only hides the icon; the services of the modules keep running. With the AppIndicator it ends the `phcc` program; on GNOME it disables the extension. In both cases the icon comes back at the next login or when you open "PYMEHackers Control Center" from the applications menu.

## Module catalogue

"Module catalogue" lists the modules published in [PHCC-modules](https://github.com/pymehackers/PHCC-modules), with Systems modules first and then Cybersecurity modules, each group sorted by name.

| What you see | Meaning |
|---|---|
| "Loading the catalogue…" | The list is being downloaded |
| "The catalogue could not be loaded" | No connection to GitHub, or another error (see [Troubleshooting](#troubleshooting)) |
| "(no modules available)" | The repository has no valid module |
| "An operation is in progress…" | A module is being installed or removed; the actions are disabled until it ends |
| "Example 1.2.0" | Module not installed, with the version available |
| "Example 1.1.0 (installed)" | Module installed, with the installed version |
| "Example (not available for this platform)" | The module does not support this Debian architecture; it cannot be selected |

Open a module to see its description and its actions:

- "Install" for modules that are not installed.
- "Update to 1.2.0" when the installed version differs from the published one.
- "Reinstall" and "Uninstall" for installed modules.

When you choose an action, polkit asks for an administrator password (on Debian, the root password, or your own password if your user belongs to the `sudo` group). While the session stays active, polkit remembers the authorisation for a few minutes. A notification announces the start ("Installing Example…", "Updating Example…", "Reinstalling Example…", "Uninstalling Example…") and another one the result:

- "Example: operation completed."
- "Example: the operation failed. Details in /var/log/phcc-modules.log."
- "Example: authorisation cancelled." (the password dialog was closed)
- "Example: not authorised, or no authentication agent is available." (the password was wrong, or there is no polkit agent in the session)

When the operation ends, the catalogue and the sections are reloaded, so a newly installed module appears under "Systems" or "Cybersecurity" at once and an uninstalled one disappears.

The catalogue is kept for 10 minutes. "Refresh catalogue" downloads it again immediately and also rebuilds the sections (useful after installing a module from a terminal). Every installation always uses a freshly downloaded catalogue.

## Languages

The core follows the language of your session (the `LANGUAGE`, `LC_ALL`, `LC_MESSAGES` and `LANG` variables, in that order):

| Session locale | Language of the core |
|---|---|
| `en_GB` | en-GB |
| `en_US` and any other `en_*` | en-US |
| `es_AR` | es-AR |
| `es_ES` and any other `es_*` (`es_MX`, `es_CL`...) | es-ES |
| Anything else | en-US |

After changing the language of the session, log out and log back in. Module names and actions come from each module and use the translations that the module provides. The password dialog uses the translations of the polkit policy.

## Logs

- **Module operations**: `/var/log/phcc-modules.log` (readable by root). Each operation adds lines with the UTC date in the project format, followed by the full output of the module installer:

  ```text
  2026-10-29@13-59-59.723 install example: started
  2026-10-29@14-00-41.118 install example: completed
  ```

  The first line means the operation started at 2026/10/29@13:59:59.723 (UTC). Read it as root with `tail -n 50 /var/log/phcc-modules.log`.
- **Installation of the core**: `/root/phcc-install.log`.
- **Messages of the indicator**: the session log, for example `journalctl --user -b | grep PYMEHackers` or `~/.xsession-errors`, depending on the desktop.
- **Messages of the GNOME extension**: `journalctl -b /usr/bin/gnome-shell | grep "PYMEHackers Control Center"`.

## Command-line use

The catalogue helper can also be used from a terminal:

```bash
# List the catalog (as any user); --refresh skips the 10-minute cache
/usr/libexec/phcc/phcc-modules list --refresh

# Install, update, reinstall or uninstall a module (as root)
/usr/libexec/phcc/phcc-modules install example
/usr/libexec/phcc/phcc-modules uninstall example

# The same from a normal user, with the polkit password dialog
pkexec /usr/libexec/phcc/phcc-modules reinstall example
```

`list` prints one module per line with 7 TAB-separated fields: id, section, available version, installed version, supported (`1`) or not (`0`), name and description. Errors are printed on the terminal, which makes this the best way to find out why "The catalogue could not be loaded" appears.

`phcc-show` shows the icon from a terminal in the same way as the applications-menu entry.

## Upgrade, reinstall and uninstall

Run as root:

```bash
# Upgrade (or install): does nothing if the installed version is already the published one
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash

# Reinstall the same version
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash -s -- --reinstall

# Uninstall the core
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

`--uninstall` runs `apt-get remove phcc`. The installed modules and their services stay as they are, the build tools installed by the installer stay installed, and `/var/log/phcc-modules.log` is kept. To delete the log and the empty module folders as well, run `apt-get purge phcc`. If you also want to remove the modules, uninstall them from "Module catalogue" before removing the core; afterwards, each module can still be removed with its own installer and the `--uninstall` argument (see its documentation in PHCC-modules).

The installer always installs the version published in the repository, even when it is older than the installed one.

## Troubleshooting

| Problem | What to do |
|---|---|
| No icon on GNOME | Open "PYMEHackers Control Center" from the applications menu. Check `gnome-extensions info phcc@pymehackers.com`; if the Shell does not know it, log out and log back in. Check that user extensions are not disabled: `gsettings get org.gnome.shell disable-user-extensions` must print `false`. GNOME older than 45 is not supported. |
| No icon on MATE, XFCE, KDE... | Check whether the program is running with `pgrep -u "$USER" -x phcc`; if not, start it with `phcc` from a terminal and read its messages. Make sure the panel has a notification area or status notifier applet. |
| No icon on Budgie or GNOME Flashback | These sessions declare themselves as GNOME but do not run GNOME Shell, so neither the extension nor the autostart of `phcc` applies. Run `phcc` manually or add it to the startup applications of the session. |
| "The catalogue could not be loaded" | Check the Internet connection and the date and time of the machine (HTTPS fails with a wrong clock). Run `/usr/libexec/phcc/phcc-modules list --refresh` in a terminal to see the error. The GitHub API allows 60 unauthenticated requests per hour from the same public IP address; if many machines share it, wait and use "Refresh catalogue" later. |
| "(no modules available)" | The repository has no valid module yet, or none has a correct `module.json`. |
| A module appears as "(not available for this platform)" | The module does not support `debian-amd64` or `debian-arm64` (the one of your machine). |
| No password dialog appears and the notification says "not authorised, or no authentication agent is available" | Start a polkit authentication agent in your session (see [Requirements](#requirements)). |
| "...the operation failed. Details in /var/log/phcc-modules.log." | Read the end of the log as root: the output of the module installer explains the error. |
| A module is installed but does not appear in its section | The module must install its manifest in `/usr/share/pymehackers/modules/sys/` or `/usr/share/pymehackers/modules/cs/`. Use "Refresh catalogue", or quit and start the indicator again. |
| A module that was removed from the repository cannot be uninstalled from the catalogue | Use the module's own installer with `--uninstall`, or remove its package with `apt-get remove`. |
| No notifications on desktops other than GNOME | Install `libnotify-bin`. |
| The one-line installer fails | Read `/root/phcc-install.log`. It must run as root, on Debian or a derivative, with access to GitHub. |

Notes on the pending platforms: [macOS](macos/MANUAL.en-GB.md), [Windows](windows/MANUAL.en-GB.md).
