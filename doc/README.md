# PYMEHackers Control Center

This README is also available in:\
[en-GB](README.en-GB.md), en-US, [es-AR](README.es-AR.md), [es-ES](README.es-ES.md)

## What is it

PHCC is a desktop-only application. Debian is currently implemented; macOS and Windows are pending.

PYMEHackers Control Center (PHCC) gathers the PYMEHackers systems and cybersecurity tools, called modules, in a single menu with two sections: Systems and Cybersecurity.

- On Debian it adds an icon to the top bar of the desktop (GNOME Shell, MATE, XFCE, Cinnamon, KDE…).

This repository is the core and ships no module. Its Module catalog lists the modules published in [PHCC-modules](https://github.com/pymehackers/PHCC-modules) and installs, updates, reinstalls or uninstalls them with a click.

## Screenshots

![PYMEHackers Control Center menu](https://raw.githubusercontent.com/pymehackers/PHCC/main/doc/screenshot.png)

## Install

Run it as `root`.

**Debian** (amd64 or arm64, with a graphical desktop):

```bash
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash
```

Then install the modules you want from the **Module catalog** menu.

## Read the documentation

Explore:

- [doc/MANUAL.md](MANUAL.md) to learn how to install it and use it.
- [doc/CODE.md](CODE.md) to understand how it is built (for developers and for AI models).

## Sponsor this project

- **[Hire me](mailto:nipegun@gmail.com?subject=I%20want%20to%20hire%20you%21)** to add new features.
- **GitHub Sponsors.** You can also support the project financially on GitHub: [github.com/sponsors/nipegun](https://github.com/sponsors/nipegun).
