#!/bin/bash

set -euo pipefail

# Cross-compiles the base software (phcc indicator) for Debian ARM64 (aarch64) from an amd64 host,
# produces the VERIFIED arm64 .deb package (including the "core WITHOUT modules" guard) and leaves
# it in ./dist/.
#
# It does not duplicate code or data: it REUSES the Makefile (app-debian/build/Makefile), the
# control template and the maintainer scripts (app-debian/build/debian/) and the assets of
# app-debian/frontend/ and app-debian/backend/ (indicator.c, the GNOME extension, the icons, the
# autostart, the launchers, the module catalog helper, the polkit policy and the language files
# are the same ones build-deb.sh packages). Only the compiler (cross), the libraries (arm64 through
# multiarch) and the Architecture field of the control (amd64 -> arm64) change. The base software
# is packaged EMPTY, without modules.
#
# It requires the cross-toolchain and the arm64 libs (see install-build-dependencies.sh).
#
# NOTE: the "set -euo pipefail" + "if ! fMain" template disables set -e inside fMain (Bash ignores
# -e in the operand of '!'). That is why every critical phase is checked EXPLICITLY.
#
# Usage:
#   ./build.sh                 cross-compiles, packages, verifies and collects the arm64 .deb in dist/
#   ./build.sh --install-deps  installs the cross-toolchain and the arm64 libs first (sudo)
#   ./build.sh --clean         removes dist/ and the arm64 build before building
#   ./build.sh --help

cScriptDir="$(cd "$(dirname "$0")" && pwd)"
cBuildRoot="$(cd "${cScriptDir}/.." && pwd)"
cAppDir="$(cd "${cBuildRoot}/.." && pwd)"
cFrontendDir="${cAppDir}/frontend"
cBackendDir="${cAppDir}/backend"
cTriplet="aarch64-linux-gnu"
cCross="${cTriplet}-gcc"
cArch="arm64"
cPkgConfigLibdir="/usr/lib/${cTriplet}/pkgconfig"
cBuildSub="out-arm64"
cBuildDir="${cBuildRoot}/${cBuildSub}"
cBin="${cBuildDir}/phcc"
cControlAmd64="${cBuildRoot}/debian/control"
cPkg="phcc"
cDistDir="${cScriptDir}/dist"
vStageDir=""
vPackageTempDir=""
vArtifactTemporary=""

vInstallDeps="no"
vClean="no"

fCleanup() {
  if [ -n "${vStageDir}" ] && [ -d "${vStageDir}" ]; then
    rm -rf "${vStageDir}"
  fi
  if [ -n "${vPackageTempDir}" ] && [ -d "${vPackageTempDir}" ]; then
    rm -rf "${vPackageTempDir}"
  fi
  if [ -n "${vArtifactTemporary}" ] && [ -f "${vArtifactTemporary}" ]; then
    rm -f "${vArtifactTemporary}"
  fi
}

trap fCleanup EXIT

fShowHelp() {
  echo "Usage: build.sh [--install-deps] [--clean] [--help]"
  echo "  --install-deps   installs the cross-toolchain and the arm64 libs first (sudo)"
  echo "  --clean          removes dist/ and the arm64 build (../out-arm64) before building"
  echo "  --help           shows this help"
}

fCheckEnvironment() {
  if [ ! -f "${cBuildRoot}/Makefile" ]; then
    echo "The reused Makefile was not found: ${cBuildRoot}/Makefile"
    return 1
  fi
  if [ ! -f "${cControlAmd64}" ]; then
    echo "The base control file was not found: ${cControlAmd64}"
    return 1
  fi
  for vBin in chmod cmp cp dpkg-deb file install make mkdir mktemp mv pkg-config sed; do
    if ! command -v "${vBin}" > /dev/null 2>&1; then
      echo "The tool '${vBin}' is missing."
      return 1
    fi
  done
}

fCheckDependencies() {
  vMissing=""
  if ! command -v "${cCross}" > /dev/null 2>&1; then
    vMissing="${vMissing} ${cCross}"
  fi
  if ! PKG_CONFIG_LIBDIR="${cPkgConfigLibdir}" pkg-config --exists gtk+-3.0 ayatana-appindicator3-0.1 2> /dev/null; then
    vMissing="${vMissing} libgtk-3-dev:arm64/libayatana-appindicator3-dev:arm64"
  fi
  if [ -n "${vMissing}" ]; then
    echo "Missing cross-compilation dependencies:${vMissing}"
    echo "Run first:  ${cScriptDir}/install-build-dependencies.sh"
    echo "  (or call this script again with --install-deps)"
    return 1
  fi
}

fReadVersion() {
  if ! vVersion="$(sed -n 's/^Version:[[:space:]]*//p' "${cControlAmd64}" | head -n1)"; then
    echo "Could not query the version from ${cControlAmd64}"
    return 1
  fi
  if [ -z "${vVersion}" ]; then
    echo "Could not read the version from ${cControlAmd64}"
    return 1
  fi
}

fCompile() {
  echo "==> Cross-compiling the indicator for ${cArch} (${cCross})"
  if ! PKG_CONFIG_LIBDIR="${cPkgConfigLibdir}" PKG_CONFIG_SYSROOT_DIR="/" \
       make -C "${cBuildRoot}" all CC="${cCross}" BUILDDIR="${cBuildSub}"; then
    echo "The cross-compilation of the indicator failed."
    return 1
  fi
  if [ ! -f "${cBin}" ]; then
    echo "The cross-compilation did not produce the expected binary: ${cBin}"
    return 1
  fi
  if ! vFile="$(file -b "${cBin}")"; then
    echo "Could not identify the architecture of ${cBin}"
    return 1
  fi
  echo "    ${vFile}"
  if ! printf '%s' "${vFile}" | grep -qi 'aarch64'; then
    echo "The binary is not ARM64 (aarch64): ${vFile}"
    return 1
  fi
}

fPackage() {
  if ! vStageDir="$(mktemp -d)"; then
    echo "Could not create the temporary packaging directory."
    return 1
  fi
  vPkgName="${cPkg}_${vVersion}_${cArch}"
  vPkgDir="${vStageDir}/${vPkgName}"

  # Same assets and modes as the native package (build-deb.sh); only the binary (arm64) and the
  # control change.
  if ! install -D -m 0755 "${cBin}" "${vPkgDir}/usr/bin/phcc" \
    || ! install -D -m 0644 "${cFrontendDir}/desktop/phcc.desktop" \
      "${vPkgDir}/etc/xdg/autostart/phcc.desktop"; then
    echo "Could not install the base files of the indicator."
    return 1
  fi

  # Wrapper, menu launcher and GNOME auto-activation autostart (same as build-deb.sh).
  if ! install -D -m 0755 "${cBackendDir}/phcc-show" \
    "${vPkgDir}/usr/bin/phcc-show" \
    || ! install -D -m 0644 \
      "${cFrontendDir}/desktop/pymehackers-control-center.desktop" \
      "${vPkgDir}/usr/share/applications/pymehackers-control-center.desktop" \
    || ! install -D -m 0644 "${cFrontendDir}/desktop/phcc-gnome-activate.desktop" \
      "${vPkgDir}/etc/xdg/autostart/phcc-gnome-activate.desktop"; then
    echo "Could not install the desktop launchers."
    return 1
  fi

  # Module catalog helper (lists and installs the modules of the PHCC-modules repository) and the
  # polkit policy that lets pkexec run it as root after authentication (same as build-deb.sh).
  if ! install -D -m 0755 "${cBackendDir}/phcc-modules" \
    "${vPkgDir}/usr/libexec/phcc/phcc-modules" \
    || ! install -D -m 0644 "${cBackendDir}/polkit/com.pymehackers.phcc.modules.policy" \
      "${vPkgDir}/usr/share/polkit-1/actions/com.pymehackers.phcc.modules.policy"; then
    echo "Could not install the module catalog helper."
    return 1
  fi

  cExtDir="${vPkgDir}/usr/share/gnome-shell/extensions/phcc@pymehackers.com"
  if ! install -D -m 0644 "${cFrontendDir}/gnome-extension/metadata.json" \
    "${cExtDir}/metadata.json" \
    || ! install -D -m 0644 "${cFrontendDir}/gnome-extension/extension.js" \
      "${cExtDir}/extension.js" \
    || ! install -D -m 0644 "${cFrontendDir}/gnome-extension/stylesheet.css" \
      "${cExtDir}/stylesheet.css"; then
    echo "Could not install the GNOME Shell extension."
    return 1
  fi

  # Language files shared by the indicator, the GNOME extension and the backend scripts.
  for vLang in en-GB en-US es-AR es-ES; do
    if ! install -D -m 0644 "${cFrontendDir}/lang/${vLang}.json" \
      "${vPkgDir}/usr/share/pymehackers/core/lang/${vLang}.json"; then
      echo "Could not install the language file ${vLang}.json."
      return 1
    fi
  done

  if ! install -D -m 0644 "${cFrontendDir}/icons/phcc.svg" \
    "${vPkgDir}/usr/share/icons/hicolor/scalable/apps/phcc.svg" \
    || ! install -D -m 0644 "${cFrontendDir}/icons/phcc-symbolic.svg" \
      "${vPkgDir}/usr/share/icons/hicolor/symbolic/apps/phcc-symbolic.svg"; then
    echo "Could not install the SVG icons."
    return 1
  fi
  for vSize in 16 22 24 32 48 64 128 256 512; do
    if ! install -D -m 0644 "${cFrontendDir}/icons/phcc-${vSize}.png" \
      "${vPkgDir}/usr/share/icons/hicolor/${vSize}x${vSize}/apps/phcc.png"; then
      echo "Could not install the ${vSize}x${vSize} PNG icon."
      return 1
    fi
  done

  # Module registry directories (empty; the core ships without modules).
  if ! install -d -m 0755 "${vPkgDir}/usr/share/pymehackers/modules/sys" \
    || ! install -d -m 0755 "${vPkgDir}/usr/share/pymehackers/modules/cs"; then
    echo "Could not create the module registry directories."
    return 1
  fi

  # Control derived from the amd64 template changing only the architecture.
  if ! install -d -m 0755 "${vPkgDir}/DEBIAN"; then
    echo "Could not create the metadata directory."
    return 1
  fi
  if ! sed 's/^Architecture:[[:space:]]*amd64/Architecture: arm64/' "${cControlAmd64}" > "${vPkgDir}/DEBIAN/control"; then
    echo "Could not derive the arm64 control file."
    return 1
  fi
  if ! grep -q '^Architecture: arm64' "${vPkgDir}/DEBIAN/control"; then
    echo "The derived control file was not left with Architecture: arm64."
    return 1
  fi
  if ! chmod 0644 "${vPkgDir}/DEBIAN/control"; then
    echo "Could not set the permissions of the arm64 control file."
    return 1
  fi
  if ! install -D -m 0755 "${cBuildRoot}/debian/postinst" \
    "${vPkgDir}/DEBIAN/postinst" \
    || ! install -D -m 0755 "${cBuildRoot}/debian/postrm" \
      "${vPkgDir}/DEBIAN/postrm"; then
    echo "Could not install the maintainer scripts."
    return 1
  fi

  if ! mkdir -p "${cBuildDir}"; then
    echo "Could not create the build directory."
    return 1
  fi
  vDeb="${cBuildDir}/${vPkgName}.deb"
  if ! vPackageTempDir="$(mktemp -d -p "${cBuildDir}" ".${vPkgName}.XXXXXX")"; then
    echo "Could not create the temporary package directory."
    return 1
  fi
  vPackageTemporary="${vPackageTempDir}/${vPkgName}.deb"
  if ! dpkg-deb --root-owner-group --build "${vPkgDir}" "${vPackageTemporary}"; then
    echo "dpkg-deb failed to build the package."
    return 1
  fi
  if [ ! -s "${vPackageTemporary}" ]; then
    echo "No valid package was produced: ${vPackageTemporary}"
    return 1
  fi
  if [ "$(dpkg-deb -f "${vPackageTemporary}" Package)" != "${cPkg}" ] \
    || [ "$(dpkg-deb -f "${vPackageTemporary}" Version)" != "${vVersion}" ] \
    || [ "$(dpkg-deb -f "${vPackageTemporary}" Architecture)" != "${cArch}" ]; then
    echo "The metadata of the produced package does not match its name."
    return 1
  fi
  if ! chmod 0644 "${vPackageTemporary}" \
    || ! mv -f "${vPackageTemporary}" "${vDeb}"; then
    echo "Could not publish the validated package."
    return 1
  fi
  if ! rmdir "${vPackageTempDir}"; then
    echo "Could not remove the temporary package directory."
    return 1
  fi
  vPackageTempDir=""
  echo "==> Package built: ${vDeb}"
}

fVerify() {
  echo ""
  echo "==> Verifying ${vDeb}"
  if ! dpkg-deb --info "${vDeb}" | grep -E 'Package:|Version:|Architecture:'; then
    echo "Could not read the package metadata."
    return 1
  fi
  if ! vContent="$(dpkg-deb --contents "${vDeb}")"; then
    echo "Could not obtain the package content."
    return 1
  fi

  echo "--- Checking mandatory paths ---"
  aRequiredPaths=(
    "\./usr/bin/phcc$"
    "\./usr/bin/phcc-show$"
    "\./usr/libexec/phcc/phcc-modules$"
    "\./usr/share/polkit-1/actions/com\.pymehackers\.phcc\.modules\.policy$"
    "\./etc/xdg/autostart/phcc\.desktop$"
    "\./etc/xdg/autostart/phcc-gnome-activate\.desktop$"
    "\./usr/share/applications/pymehackers-control-center\.desktop$"
    "\./usr/share/gnome-shell/extensions/phcc@pymehackers\.com/extension\.js$"
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
    echo "Verification failed: ${vFailures} mandatory path(s) missing."
    return 1
  fi

  # "Base software WITHOUT modules" guard (identical to the native flow of the core). The module
  # catalog helper (phcc-modules) is part of the core and does not match "phcc-mod-".
  echo "--- Checking that the core does NOT include modules ---"
  aForbiddenPaths=(
    "\./usr/share/pymehackers/modules/(sys|cs)/.+"
    "phcc-mod-"
    "\./etc/pymehackers/"
  )
  vIntruders=0
  for vPattern in "${aForbiddenPaths[@]}"; do
    if printf '%s\n' "${vContent}" | grep -Eq -- "${vPattern}"; then
      echo "  INTRUDER ${vPattern}"
      vIntruders=$((vIntruders + 1))
    else
      echo "  OK      no matches for: ${vPattern}"
    fi
  done
  if [ "${vIntruders}" -gt 0 ]; then
    echo "Verification failed: the core package contains module pieces (it must ship empty)."
    return 1
  fi
  echo "Verification passed: arm64 package with all the paths and WITHOUT modules."
}

fCollectArtifact() {
  vDebDist="${cDistDir}/${vPkgName}.deb"
  if ! mkdir -p "${cDistDir}"; then
    echo "Could not create the artifacts directory: ${cDistDir}"
    return 1
  fi
  if ! vArtifactTemporary="$(mktemp "${cDistDir}/.${vPkgName}.deb.XXXXXX")"; then
    echo "Could not create the temporary artifact."
    return 1
  fi
  if ! cp "${vDeb}" "${vArtifactTemporary}" \
    || ! cmp -s "${vDeb}" "${vArtifactTemporary}" \
    || ! chmod 0644 "${vArtifactTemporary}" \
    || ! mv -f "${vArtifactTemporary}" "${vDebDist}"; then
    echo "Could not publish the package in ${cDistDir}"
    return 1
  fi
  vArtifactTemporary=""
  echo "==> Final package collected in: ${vDebDist}"
}

fMain() {
  for vArg in "$@"; do
    case "${vArg}" in
      --install-deps) vInstallDeps="yes" ;;
      --clean) vClean="yes" ;;
      -h | --help) fShowHelp; return 0 ;;
      *) echo "Unrecognized argument: ${vArg}"; fShowHelp; return 1 ;;
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
    echo "==> Cleaning dist/ and ${cBuildDir}"
    if ! rm -rf "${cDistDir}" "${cBuildDir}"; then
      echo "Could not clean the previous artifacts."
      return 1
    fi
  fi

  if ! fReadVersion;      then return 1; fi
  if ! fCompile;          then return 1; fi
  if ! fPackage;          then return 1; fi
  if ! fVerify;           then return 1; fi
  if ! fCollectArtifact;  then return 1; fi

  echo ""
  echo "Done. Verified arm64 .deb package of the core in: ${cDistDir}/"
}

if ! fMain "$@"; then
  echo "error cross-compiling/packaging the core for arm64"
  exit 1
fi
