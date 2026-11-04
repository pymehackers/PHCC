#!/bin/bash

set -euo pipefail

# Installs the BUILD dependencies of the core (base software "phcc") of PYMEHackers Control Center
# for Debian on the native architecture of the build host. The indicator (indicator.c) links
# against GTK3 and libayatana-appindicator, so their -dev packages are needed, besides the build
# tools (gcc, make) and pkg-config. The RUNTIME dependencies (libgtk-3-0,
# libayatana-appindicator3-1, ...) are declared by the .deb package itself; only what is needed to
# build it is installed here.
#
# The script is idempotent: if the libraries are already available to pkg-config, apt is not touched.

cAptPackages="build-essential pkg-config libgtk-3-dev libayatana-appindicator3-dev"

fCleanup() {
  # No temporary files are created; nothing to clean.
  :
}

trap fCleanup EXIT

fIsRoot() {
  [ "$(id -u)" -eq 0 ]
}

fMain() {
  # If the development dependencies are already present, there is nothing to do (idempotency).
  if pkg-config --exists gtk+-3.0 && pkg-config --exists ayatana-appindicator3-0.1; then
    echo "The build dependencies are already installed. Nothing to do."
    return 0
  fi

  # Determine the privilege prefix: none if we already are root, sudo otherwise.
  if fIsRoot; then
    aPriv=()
  else
    if ! command -v sudo > /dev/null 2>&1; then
      echo "Root privileges are needed and 'sudo' is not available. Run the script as root."
      return 1
    fi
    aPriv=(sudo)
  fi

  # NOTE: the "if ! fMain" template disables set -e inside fMain, so every apt step is checked
  # explicitly instead of relying on set -e.
  echo "==> Updating apt indexes"
  if ! "${aPriv[@]}" apt-get update < /dev/tty; then
    echo "'apt-get update' failed."
    return 1
  fi

  echo "==> Installing build dependencies: ${cAptPackages}"
  if ! "${aPriv[@]}" apt-get install -y ${cAptPackages} < /dev/tty; then
    echo "The installation of the build packages failed."
    return 1
  fi

  # Check that, after installing, pkg-config really finds the modules.
  vMissing=""
  for vModule in gtk+-3.0 ayatana-appindicator3-0.1; do
    if ! pkg-config --exists "${vModule}"; then
      vMissing="${vMissing} ${vModule}"
    fi
  done
  if [ -n "${vMissing}" ]; then
    echo "After the installation some pkg-config modules are still missing:${vMissing}"
    return 1
  fi

  echo "==> Build dependencies installed successfully."
}

if ! fMain; then
  echo "error installing the build dependencies"
  exit 1
fi
