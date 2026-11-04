#!/bin/bash

set -euo pipefail

# Builds the core (base software "phcc") of PYMEHackers Control Center for Debian on the native
# architecture of the build host (amd64, arm64...), produces the final .deb package and verifies it
# before leaving it in ./dist/.
#
# It reuses the official core packager (../build-deb.sh), which builds the indicator with make and
# assembles the package tree with dpkg-deb. This script adds the dependency check, validates that
# the build produced the binary, verifies the content of the .deb and only then collects it in
# ./dist/.
#
# NOTE: the "set -euo pipefail" + "if ! fMain" template disables set -e inside fMain (Bash rule:
# -e is ignored in the operand of '!'). That is why every critical phase is checked EXPLICITLY
# with "if ! fPhase; then return 1; fi", without relying on set -e inside fMain.
#
# Usage:
#   ./build.sh                 builds, verifies and collects the .deb in dist/
#   ./build.sh --clean         removes previous artifacts before building
#   ./build.sh --install-deps  installs the build dependencies first (sudo)
#   ./build.sh --help          shows this help

cScriptDir="$(cd "$(dirname "$0")" && pwd)"
cBuildRoot="$(cd "${cScriptDir}/.." && pwd)"
cBuildDeb="${cBuildRoot}/build-deb.sh"
cControl="${cBuildRoot}/debian/control"
cBinary="${cBuildRoot}/out/phcc"
cDistDir="${cScriptDir}/dist"
cPkg="phcc"
vVersion=""
vArch=""
vDebName=""
vDebBuild=""
vDebDist=""
vArtifactTemporary=""

fCleanup() {
  if [ -n "${vArtifactTemporary}" ] && [ -f "${vArtifactTemporary}" ]; then
    rm -f "${vArtifactTemporary}"
  fi
}

trap fCleanup EXIT

fShowHelp() {
  echo "Usage: build.sh [--clean] [--install-deps] [--help]"
  echo "  --clean          removes out/ of app-debian/build and dist/ before building"
  echo "  --install-deps   installs the build dependencies first (sudo)"
  echo "  --help           shows this help"
}

fCheckEnvironment() {
  # The official core packager must exist and be executable.
  if [ ! -x "${cBuildDeb}" ]; then
    echo "The core packager was not found or is not executable: ${cBuildDeb}"
    return 1
  fi
}

fCheckDependencies() {
  vMissing=""
  for vModule in gtk+-3.0 ayatana-appindicator3-0.1; do
    if ! pkg-config --exists "${vModule}" 2> /dev/null; then
      vMissing="${vMissing} ${vModule}"
    fi
  done
  for vBin in gcc make dpkg-deb pkg-config; do
    if ! command -v "${vBin}" > /dev/null 2>&1; then
      vMissing="${vMissing} ${vBin}"
    fi
  done
  if [ -n "${vMissing}" ]; then
    echo "Missing build dependencies:${vMissing}"
    echo "Run first:  ${cScriptDir}/install-build-dependencies.sh"
    echo "  (or call this script again with --install-deps)"
    return 1
  fi
}

fReadVersion() {
  if ! vVersion="$(sed -n 's/^Version:[[:space:]]*//p' "${cControl}" | head -n1)"; then
    echo "Could not query the version from ${cControl}"
    return 1
  fi
  if [ -z "${vVersion}" ]; then
    echo "Could not read the version from ${cControl}"
    return 1
  fi
}

fReadArch() {
  # The package is built for the native architecture of the host (the same one build-deb.sh uses).
  if ! vArch="$(dpkg --print-architecture)"; then
    echo "Could not determine the native Debian architecture (dpkg --print-architecture)."
    return 1
  fi
  if [ -z "${vArch}" ]; then
    echo "dpkg --print-architecture returned an empty architecture."
    return 1
  fi
}

fBuildAndPackage() {
  echo "==> Building and packaging the core with build-deb.sh"
  # build-deb.sh moves to app-debian/build/ by itself and leaves the .deb in app-debian/build/out/.
  if ! "${cBuildDeb}"; then
    echo "The packager build-deb.sh returned an error."
    return 1
  fi
  # build-deb.sh might not abort even if the build fails; checking the binary explicitly
  # guarantees that a build failure does not go unnoticed.
  if [ ! -f "${cBinary}" ]; then
    echo "The build did not produce the expected binary: ${cBinary}"
    return 1
  fi
  if [ ! -f "${vDebBuild}" ]; then
    echo "The expected package was not produced: ${vDebBuild}"
    return 1
  fi
}

fVerify() {
  local pDeb="${1}"
  echo ""
  echo "==> Verifying ${pDeb}"
  echo "--- Package metadata (dpkg-deb --info) ---"
  if ! dpkg-deb --info "${pDeb}"; then
    echo "Could not read the package metadata."
    return 1
  fi
  echo "--- Package content (dpkg-deb --contents) ---"
  if ! dpkg-deb --contents "${pDeb}"; then
    echo "Could not list the package content."
    return 1
  fi

  echo "--- Checking mandatory paths ---"
  if ! vContent="$(dpkg-deb --contents "${pDeb}")"; then
    echo "Could not obtain the package content."
    return 1
  fi
  aRequiredPaths=(
    "\./usr/bin/phcc$"
    "\./usr/bin/phcc-show$"
    "\./usr/libexec/phcc/phcc-modules$"
    "\./usr/share/polkit-1/actions/com\.pymehackers\.phcc\.modules\.policy$"
    "\./etc/xdg/autostart/phcc\.desktop$"
    "\./etc/xdg/autostart/phcc-gnome-activate\.desktop$"
    "\./usr/share/applications/pymehackers-control-center\.desktop$"
    "\./usr/share/gnome-shell/extensions/phcc@pymehackers\.com/extension\.js$"
    "\./usr/share/gnome-shell/extensions/phcc@pymehackers\.com/metadata\.json$"
    "\./usr/share/pymehackers/core/lang/en-GB\.json$"
    "\./usr/share/pymehackers/core/lang/en-US\.json$"
    "\./usr/share/pymehackers/core/lang/es-AR\.json$"
    "\./usr/share/pymehackers/core/lang/es-ES\.json$"
    "\./usr/share/icons/hicolor/scalable/apps/phcc\.svg$"
    "\./usr/share/icons/hicolor/symbolic/apps/phcc-symbolic\.svg$"
    "\./usr/share/icons/hicolor/48x48/apps/phcc\.png$"
    "\./usr/share/pymehackers/modules/sys/$"
    "\./usr/share/pymehackers/modules/cs/$"
  )
  vFailures=0
  for vPattern in "${aRequiredPaths[@]}"; do
    if printf '%s\n' "${vContent}" | grep -Eq -- "${vPattern}"; then
      echo "  OK      ${vPattern}"
    else
      echo "  MISSING ${vPattern}"
      vFailures=$((vFailures + 1))
    fi
  done
  if [ "${vFailures}" -gt 0 ]; then
    echo "Verification failed: ${vFailures} mandatory path(s) missing from the package."
    return 1
  fi
  echo "Verification passed: the package contains all the mandatory paths."

  # --- "Base software WITHOUT modules" guard ---
  # The Control Center ships empty: it brings the module registry directories (sys/ and cs/) but
  # NO module inside them. If the core .deb carried a module manifest, a module binary/service
  # (phcc-mod-*) or module configuration, the packaging would be wrong; it aborts so that dist/
  # only holds a clean core. The module catalog helper (phcc-modules) is part of the core and does
  # not match "phcc-mod-".
  echo "--- Checking that the core does NOT include modules ---"
  aForbiddenPaths=(
    "\./usr/share/pymehackers/modules/(sys|cs)/.+"
    "phcc-mod-"
    "\./etc/pymehackers/"
  )
  vIntruders=0
  for vPattern in "${aForbiddenPaths[@]}"; do
    vMatches="$(printf '%s\n' "${vContent}" | grep -E -- "${vPattern}" || true)"
    if [ -n "${vMatches}" ]; then
      echo "  INTRUDER (${vPattern}):"
      printf '%s\n' "${vMatches}" | sed 's/^/    /'
      vIntruders=$((vIntruders + 1))
    else
      echo "  OK      no matches for: ${vPattern}"
    fi
  done
  if [ "${vIntruders}" -gt 0 ]; then
    echo "Verification failed: the core package contains module pieces (it must ship empty)."
    return 1
  fi

  # The registry directories must exist but be EMPTY (only the folder, without manifests).
  for vSection in sys cs; do
    if ! printf '%s\n' "${vContent}" | grep -Eq -- "\./usr/share/pymehackers/modules/${vSection}/$"; then
      echo "Verification failed: the module registry directory is missing: ${vSection}/"
      return 1
    fi
  done
  echo "Verification passed: the core does not include modules (registry sys/, cs/ present and empty)."
}

fCollectArtifact() {
  if ! mkdir -p "${cDistDir}"; then
    echo "Could not create the artifacts directory: ${cDistDir}"
    return 1
  fi
  if ! vArtifactTemporary="$(mktemp "${cDistDir}/.${vDebName}.XXXXXX")"; then
    echo "Could not create the temporary artifact."
    return 1
  fi
  if ! cp "${vDebBuild}" "${vArtifactTemporary}" \
    || ! cmp -s "${vDebBuild}" "${vArtifactTemporary}" \
    || ! chmod 0644 "${vArtifactTemporary}" \
    || ! mv -f "${vArtifactTemporary}" "${vDebDist}"; then
    echo "Could not publish the package in ${cDistDir}"
    return 1
  fi
  vArtifactTemporary=""
  echo "==> Final package collected in: ${vDebDist}"
}

fMain() {
  vClean="no"
  vInstallDeps="no"
  for vArg in "$@"; do
    case "${vArg}" in
      --clean)
        vClean="yes"
        ;;
      --install-deps)
        vInstallDeps="yes"
        ;;
      -h | --help)
        fShowHelp
        return 0
        ;;
      *)
        echo "Unrecognized argument: ${vArg}"
        fShowHelp
        return 1
        ;;
    esac
  done

  if ! fCheckEnvironment; then
    return 1
  fi

  if [ "${vInstallDeps}" = "yes" ]; then
    if ! "${cScriptDir}/install-build-dependencies.sh"; then
      return 1
    fi
  fi

  if ! fCheckDependencies; then
    return 1
  fi

  if [ "${vClean}" = "yes" ]; then
    echo "==> Cleaning previous artifacts (${cBuildRoot}/out and ${cDistDir})"
    if ! rm -rf "${cBuildRoot}/out" "${cDistDir}"; then
      echo "Could not clean the previous artifacts."
      return 1
    fi
  fi

  # Package name and paths: version from the control template, native architecture of the host.
  if ! fReadVersion; then
    return 1
  fi
  if ! fReadArch; then
    return 1
  fi
  vDebName="${cPkg}_${vVersion}_${vArch}.deb"
  vDebBuild="${cBuildRoot}/out/${vDebName}"
  vDebDist="${cDistDir}/${vDebName}"

  if ! fBuildAndPackage; then
    return 1
  fi

  # Verify the freshly built .deb BEFORE collecting it: that way dist/ only holds valid packages.
  if ! fVerify "${vDebBuild}"; then
    return 1
  fi

  if ! fCollectArtifact; then
    return 1
  fi

  echo ""
  echo "Done. Final verified .deb package in: ${vDebDist}"
}

if ! fMain "$@"; then
  echo "error building/packaging the core"
  exit 1
fi
