#!/bin/bash

set -euo pipefail

# Installs on a Debian amd64 host what is needed to CROSS-COMPILE the base software (phcc
# indicator) for ARM64 (aarch64):
#   - gcc-aarch64-linux-gnu              : cross compiler amd64 -> arm64.
#   - libgtk-3-dev:arm64                 : GTK3 for arm64 (the indicator links against GTK).
#   - libayatana-appindicator3-dev:arm64 : AppIndicator for arm64.
#   - pkg-config-aarch64-linux-gnu (if available): pkg-config wrapper for arm64.
#
# Cross-compilation on Debian uses MULTIARCH: the arm64 architecture is enabled in dpkg to install
# the arm64 -dev libraries next to the amd64 ones. The headers (/usr/include) are shared; only the
# .so files change (in /usr/lib/aarch64-linux-gnu).
#
# The script is idempotent. It requires sudo (it modifies the dpkg/apt of the host). The RUNTIME
# dependencies (libgtk-3-0, libayatana-appindicator3-1, ...) are declared by the .deb itself.

cTriplet="aarch64-linux-gnu"
cAptPackages="gcc-${cTriplet} file libgtk-3-dev:arm64 libayatana-appindicator3-dev:arm64"
cPkgConfigCross="pkg-config-${cTriplet}"
cPkgConfigLibdir="/usr/lib/${cTriplet}/pkgconfig"

fCleanup() {
  :
}

trap fCleanup EXIT

fIsRoot() {
  [ "$(id -u)" -eq 0 ]
}

fAllPresent() {
  if ! command -v "${cTriplet}-gcc" > /dev/null 2>&1; then
    return 1
  fi
  if ! command -v file > /dev/null 2>&1; then
    return 1
  fi
  if ! PKG_CONFIG_LIBDIR="${cPkgConfigLibdir}" pkg-config --exists gtk+-3.0 ayatana-appindicator3-0.1 2> /dev/null; then
    return 1
  fi
  return 0
}

fMain() {
  if fAllPresent; then
    echo "The arm64 cross-toolchain and the libs (GTK3, appindicator) are already available. Nothing to do."
    return 0
  fi

  if fIsRoot; then
    aPriv=()
  else
    if ! command -v sudo > /dev/null 2>&1; then
      echo "Root privileges are needed and 'sudo' is not available. Run the script as root."
      return 1
    fi
    aPriv=(sudo)
  fi

  # NOTE: the "if ! fMain" template disables set -e inside fMain; every step is checked by hand.
  echo "==> Enabling the arm64 architecture in dpkg (multiarch)"
  if ! "${aPriv[@]}" dpkg --add-architecture arm64 < /dev/tty; then
    echo "'dpkg --add-architecture arm64' failed."
    return 1
  fi

  echo "==> Updating apt indexes"
  if ! "${aPriv[@]}" apt-get update < /dev/tty; then
    echo "'apt-get update' failed. If a third-party source (e.g. CUDA) does not serve arm64, restrict"
    echo "that source with 'Architectures: amd64' in its file under /etc/apt/sources.list.d/ and retry."
    return 1
  fi

  echo "==> Installing cross-toolchain and arm64 libraries: ${cAptPackages}"
  if ! "${aPriv[@]}" apt-get install -y ${cAptPackages} ${cPkgConfigCross} < /dev/tty; then
    echo "Warning: installing everything together failed; retrying without the optional pkg-config wrapper."
    if ! "${aPriv[@]}" apt-get install -y ${cAptPackages} < /dev/tty; then
      echo "The installation of the cross-toolchain and/or the arm64 libraries failed."
      return 1
    fi
  fi

  if ! fAllPresent; then
    echo "After the installation the cross-toolchain or the arm64 libs are still not detected."
    echo "Check that '${cTriplet}-gcc' exists and that ${cPkgConfigLibdir} contains gtk+-3.0.pc."
    return 1
  fi

  echo "==> arm64 cross-toolchain and libraries installed successfully."
}

if ! fMain; then
  echo "error installing the arm64 cross-compilation dependencies"
  exit 1
fi
