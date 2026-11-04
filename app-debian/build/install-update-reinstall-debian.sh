#!/bin/bash

set -euo pipefail

# install-update-reinstall-debian.sh
# Installer of PYMEHackers Control Center (core) for Debian. Run it as root:
#
#   curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash
#
# It downloads the source of the core directly from https://github.com/pymehackers/PHCC (branch
# main), installs the build dependencies, builds the .deb for the native architecture with
# app-debian/build/native/build.sh and installs it with apt. It is idempotent:
#   (no arguments)  installs the core, or updates it when the repository has another version
#   --reinstall     builds and reinstalls it even when the same version is already installed
#   --uninstall     removes the phcc package (the installed modules are not touched)
# The whole run is logged to /root/phcc-install.log (mode 600).

cRepoOwner="pymehackers"
cRepoName="PHCC"
cRepoRef="main"
cTarballUrl="https://codeload.github.com/${cRepoOwner}/${cRepoName}/tar.gz/refs/heads/${cRepoRef}"
cPkg="phcc"
cLogFile="/root/phcc-install.log"
aBuildPackages=(build-essential pkg-config libgtk-3-dev libayatana-appindicator3-dev dpkg-dev file curl ca-certificates)

vWorkDir=""
vSourceDir=""

fCleanup() {
  if [ -n "${vWorkDir}" ] && [ -d "${vWorkDir}" ]; then
    rm -rf "${vWorkDir}"
  fi
}

trap fCleanup EXIT

fShowHelp() {
  echo "Usage: install-update-reinstall-debian.sh [--reinstall | --uninstall | --help]"
  echo "  (no arguments)  install the core, or update it to the repository version"
  echo "  --reinstall     build and reinstall it even if that version is already installed"
  echo "  --uninstall     remove the phcc package"
}

# Current UTC date in the native format of the project (2026-10-29@13-59-59.723).
fNow() {
  date -u '+%Y-%m-%d@%H-%M-%S.%3N'
}

# Sends everything this script prints to the screen and to the log file (mode 600).
fStartLog() {
  if [ ! -e "${cLogFile}" ]; then
    if ! install -m 0600 /dev/null "${cLogFile}"; then
      echo "Could not create ${cLogFile}."
      return 1
    fi
  fi
  if ! chmod 0600 "${cLogFile}"; then
    echo "Could not set the permissions of ${cLogFile}."
    return 1
  fi
  exec > >(tee -a "${cLogFile}") 2>&1
  echo ""
  echo "==> $(fNow) PYMEHackers Control Center installer started"
}

fCheckSystem() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this installer as root."
    return 1
  fi
  for vBin in apt-get dpkg dpkg-query curl tar sed; do
    if ! command -v "${vBin}" > /dev/null 2>&1; then
      echo "Missing tool '${vBin}': this installer is only for Debian and derivatives."
      return 1
    fi
  done
}

# Version of the installed phcc package, or nothing when it is not installed.
fInstalledVersion() {
  local vStatus=""
  vStatus="$(dpkg-query -W -f='${db:Status-Abbrev}|${Version}' "${cPkg}" 2> /dev/null || true)"
  case "${vStatus}" in
    ii*) echo "${vStatus#*|}" ;;
    *)   echo "" ;;
  esac
}

fUninstall() {
  if [ -z "$(fInstalledVersion)" ]; then
    echo "==> The ${cPkg} package is not installed. Nothing to do."
    return 0
  fi
  echo "==> Removing the ${cPkg} package"
  if ! DEBIAN_FRONTEND=noninteractive apt-get remove -y "${cPkg}" < /dev/null; then
    echo "apt-get could not remove ${cPkg}."
    return 1
  fi
}

fInstallDependencies() {
  echo "==> Updating the apt indexes"
  if ! DEBIAN_FRONTEND=noninteractive apt-get update < /dev/null; then
    echo "'apt-get update' failed."
    return 1
  fi
  echo "==> Installing the build dependencies: ${aBuildPackages[*]}"
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${aBuildPackages[@]}" < /dev/null; then
    echo "The build dependencies could not be installed."
    return 1
  fi
}

# Downloads and extracts the source of the core; sets vSourceDir.
fDownloadSource() {
  if ! vWorkDir="$(mktemp -d)"; then
    echo "Could not create a temporary directory."
    return 1
  fi
  echo "==> Downloading ${cRepoOwner}/${cRepoName} (${cRepoRef})"
  if ! curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --retry 3 \
    -o "${vWorkDir}/source.tar.gz" "${cTarballUrl}"; then
    echo "Could not download ${cTarballUrl}"
    return 1
  fi
  if ! tar -xzf "${vWorkDir}/source.tar.gz" -C "${vWorkDir}"; then
    echo "Could not extract the source."
    return 1
  fi
  vSourceDir="${vWorkDir}/${cRepoName}-${cRepoRef}"
  if [ ! -x "${vSourceDir}/app-debian/build/native/build.sh" ]; then
    echo "The downloaded source does not contain app-debian/build/native/build.sh."
    return 1
  fi
}

# Version of the core in the downloaded source (app-debian/build/debian/control).
fRepositoryVersion() {
  sed -n 's/^Version:[[:space:]]*//p' "${vSourceDir}/app-debian/build/debian/control" | head -n1
}

fBuildAndInstall() {
  local pReinstall="${1}"
  local vArch=""
  local vVersion=""
  local vInstalled=""
  local vPackage=""
  local aApt=()

  if ! vVersion="$(fRepositoryVersion)" || [ -z "${vVersion}" ]; then
    echo "Could not read the version of the downloaded source."
    return 1
  fi
  vInstalled="$(fInstalledVersion)"
  if [ "${vInstalled}" = "${vVersion}" ] && [ "${pReinstall}" = "no" ]; then
    echo "==> ${cPkg} ${vVersion} is already installed and up to date. Use --reinstall to force it."
    return 0
  fi

  # The build toolchain is only installed when something has to be built.
  if ! fInstallDependencies; then
    return 1
  fi

  echo "==> Building ${cPkg} ${vVersion}"
  if ! "${vSourceDir}/app-debian/build/native/build.sh"; then
    echo "The build failed."
    return 1
  fi
  if ! vArch="$(dpkg --print-architecture)"; then
    echo "Could not determine the native architecture."
    return 1
  fi
  vPackage="${vSourceDir}/app-debian/build/native/dist/${cPkg}_${vVersion}_${vArch}.deb"
  if [ ! -s "${vPackage}" ]; then
    echo "The build did not produce ${vPackage}"
    return 1
  fi

  # --allow-downgrades: the repository version always wins, even when it is older.
  aApt=(install -y --allow-downgrades)
  if [ "${vInstalled}" = "${vVersion}" ]; then
    aApt+=(--reinstall)
  fi
  echo "==> Installing ${vPackage##*/}"
  if ! DEBIAN_FRONTEND=noninteractive apt-get "${aApt[@]}" "${vPackage}" < /dev/null; then
    echo "apt-get could not install the package."
    return 1
  fi
  echo "==> PYMEHackers Control Center ${vVersion} installed."
  echo "    Open \"PYMEHackers Control Center\" from the applications menu to show the icon."
}

fMain() {
  local vReinstall="no"
  local vUninstall="no"
  local vArg=""

  for vArg in "$@"; do
    case "${vArg}" in
      --reinstall) vReinstall="yes" ;;
      --uninstall) vUninstall="yes" ;;
      -h|--help)
        fShowHelp
        return 0
        ;;
      *)
        echo "Unknown argument: ${vArg}"
        fShowHelp
        return 1
        ;;
    esac
  done

  if ! fCheckSystem; then
    return 1
  fi
  if ! fStartLog; then
    return 1
  fi

  if [ "${vUninstall}" = "yes" ]; then
    if ! fUninstall; then
      return 1
    fi
    return 0
  fi

  if ! fDownloadSource; then
    return 1
  fi
  if ! fBuildAndInstall "${vReinstall}"; then
    return 1
  fi
  echo "==> $(fNow) finished"
}

if ! fMain "$@"; then
  echo "error installing PYMEHackers Control Center (details in ${cLogFile})"
  exit 1
fi
