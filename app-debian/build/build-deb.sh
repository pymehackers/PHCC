#!/bin/bash

set -euo pipefail

# Builds the .deb package of PYMEHackers Control Center (package "phcc") for the native Debian
# architecture of the build host (amd64, arm64...).
# Usage: app-debian/build/build-deb.sh   (it moves to app-debian/build/ by itself)

cPkg="phcc"
vArch=""
vVersion=""
vStageDir=""
vPackageTempDir=""

fCleanup() {
  # Remove the temporary staging directory if it exists.
  if [ -n "${vStageDir}" ] && [ -d "${vStageDir}" ]; then
    rm -rf "${vStageDir}"
  fi
  if [ -n "${vPackageTempDir}" ] && [ -d "${vPackageTempDir}" ]; then
    rm -rf "${vPackageTempDir}"
  fi
}

trap fCleanup EXIT

fMain() {
  # Move to app-debian/build/ (the folder that contains this script).
  if ! vScriptDir="$(cd "$(dirname "${0}")" && pwd)"; then
    echo "Could not resolve the directory of the packager."
    return 1
  fi
  if ! cd "${vScriptDir}"; then
    echo "Could not enter the build directory: ${vScriptDir}"
    return 1
  fi
  cFrontendDir="../frontend"
  cBackendDir="../backend"

  # Native architecture of the host and package version (read from the control template).
  if ! vArch="$(dpkg --print-architecture)" || [ -z "${vArch}" ]; then
    echo "Could not determine the native Debian architecture (dpkg --print-architecture)."
    return 1
  fi
  if ! vVersion="$(sed -n 's/^Version:[[:space:]]*//p' debian/control | head -n1)" \
    || [ -z "${vVersion}" ]; then
    echo "Could not read the version from debian/control."
    return 1
  fi

  # Build the indicator binary. NOTE: the "if ! fMain" pattern disables set -e inside fMain
  # (Bash ignores -e in the operand of '!'), so critical steps are checked explicitly; otherwise a
  # build failure would produce a corrupt .deb.
  if ! make all; then
    echo "The build failed (make all)."
    return 1
  fi
  if [ ! -f out/phcc ] || [ ! -x out/phcc ]; then
    echo "make did not produce the expected executable: out/phcc"
    return 1
  fi

  # Prepare the staging tree of the package.
  if ! vStageDir="$(mktemp -d)"; then
    echo "Could not create the temporary packaging directory."
    return 1
  fi
  vPkgName="${cPkg}_${vVersion}_${vArch}"
  vPkgDir="${vStageDir}/${vPkgName}"

  if ! install -D -m 0755 out/phcc "${vPkgDir}/usr/bin/phcc" \
    || ! install -D -m 0644 "${cFrontendDir}/desktop/phcc.desktop" \
      "${vPkgDir}/etc/xdg/autostart/phcc.desktop"; then
    echo "Could not install the base files of the indicator."
    return 1
  fi

  # Wrapper that shows the indicator according to the desktop (called by the menu launcher and by
  # the GNOME autostart): on GNOME it enables the extension, elsewhere it starts the AppIndicator.
  if ! install -D -m 0755 "${cBackendDir}/phcc-show" "${vPkgDir}/usr/bin/phcc-show" \
    || ! install -D -m 0644 "${cFrontendDir}/desktop/pymehackers-control-center.desktop" \
      "${vPkgDir}/usr/share/applications/pymehackers-control-center.desktop" \
    || ! install -D -m 0644 "${cFrontendDir}/desktop/phcc-gnome-activate.desktop" \
      "${vPkgDir}/etc/xdg/autostart/phcc-gnome-activate.desktop"; then
    echo "Could not install the desktop launchers."
    return 1
  fi

  # Module catalog helper (lists and installs the modules of the PHCC-modules repository) and the
  # polkit policy that lets pkexec run it as root after authentication.
  if ! install -D -m 0755 "${cBackendDir}/phcc-modules" \
    "${vPkgDir}/usr/libexec/phcc/phcc-modules" \
    || ! install -D -m 0644 "${cBackendDir}/polkit/com.pymehackers.phcc.modules.policy" \
      "${vPkgDir}/usr/share/polkit-1/actions/com.pymehackers.phcc.modules.policy"; then
    echo "Could not install the module catalog helper."
    return 1
  fi

  # Native GNOME Shell extension (equivalent of the AppIndicator on GNOME desktops).
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

  # PYMEHackers Control Center icons in the hicolor theme:
  # - Colour SVG (scalable) for the AppIndicator (MATE, XFCE, KDE...) and the launcher.
  # - Symbolic SVG (monochrome) for the GNOME Shell top bar, which recolours it to match the theme.
  # - Colour PNG in standard sizes as a fallback for themes without SVG support.
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

  # Module registry directories (empty; each module drops its manifest here).
  if ! install -d -m 0755 "${vPkgDir}/usr/share/pymehackers/modules/sys" \
    || ! install -d -m 0755 "${vPkgDir}/usr/share/pymehackers/modules/cs"; then
    echo "Could not create the module registry directories."
    return 1
  fi

  # Control metadata (Architecture adapted to the native one) and maintainer scripts.
  if ! install -d -m 0755 "${vPkgDir}/DEBIAN"; then
    echo "Could not create the metadata directory."
    return 1
  fi
  if ! sed "s/^Architecture:[[:space:]].*/Architecture: ${vArch}/" debian/control \
    > "${vPkgDir}/DEBIAN/control"; then
    echo "Could not derive the control file for ${vArch}."
    return 1
  fi
  if ! grep -q "^Architecture: ${vArch}$" "${vPkgDir}/DEBIAN/control"; then
    echo "The derived control file does not declare Architecture: ${vArch}."
    return 1
  fi
  if ! chmod 0644 "${vPkgDir}/DEBIAN/control" \
    || ! install -D -m 0755 debian/postinst "${vPkgDir}/DEBIAN/postinst" \
    || ! install -D -m 0755 debian/postrm "${vPkgDir}/DEBIAN/postrm"; then
    echo "Could not install the control metadata."
    return 1
  fi

  # Check that the staging tree contains the mandatory pieces before packaging
  # (catches any silent failure of the previous 'install' calls).
  for vPath in \
    "${vPkgDir}/usr/bin/phcc" \
    "${vPkgDir}/usr/bin/phcc-show" \
    "${vPkgDir}/usr/libexec/phcc/phcc-modules" \
    "${vPkgDir}/usr/share/polkit-1/actions/com.pymehackers.phcc.modules.policy" \
    "${vPkgDir}/etc/xdg/autostart/phcc.desktop" \
    "${vPkgDir}/etc/xdg/autostart/phcc-gnome-activate.desktop" \
    "${vPkgDir}/usr/share/applications/pymehackers-control-center.desktop" \
    "${cExtDir}/metadata.json" \
    "${cExtDir}/extension.js" \
    "${vPkgDir}/usr/share/pymehackers/core/lang/en-US.json" \
    "${vPkgDir}/usr/share/icons/hicolor/scalable/apps/phcc.svg" \
    "${vPkgDir}/usr/share/icons/hicolor/symbolic/apps/phcc-symbolic.svg" \
    "${vPkgDir}/usr/share/icons/hicolor/48x48/apps/phcc.png" \
    "${vPkgDir}/DEBIAN/control"; do
    if [ ! -e "${vPath}" ]; then
      echo "A mandatory piece is missing from the staging tree: ${vPath}"
      return 1
    fi
  done

  # Build and validate the package on the same filesystem before publishing it.
  if ! mkdir -p out; then
    echo "Could not create the build output directory."
    return 1
  fi
  if ! vPackageTempDir="$(mktemp -d -p out ".${vPkgName}.XXXXXX")"; then
    echo "Could not create the temporary package directory."
    return 1
  fi
  vPackageTemporary="${vPackageTempDir}/${vPkgName}.deb"
  vPackageFinal="out/${vPkgName}.deb"
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
    || [ "$(dpkg-deb -f "${vPackageTemporary}" Architecture)" != "${vArch}" ]; then
    echo "The metadata of the produced package does not match its name."
    return 1
  fi
  if ! chmod 0644 "${vPackageTemporary}" \
    || ! mv -f "${vPackageTemporary}" "${vPackageFinal}"; then
    echo "Could not publish the validated package."
    return 1
  fi
  if ! rmdir "${vPackageTempDir}"; then
    echo "Could not remove the temporary package directory."
    return 1
  fi
  vPackageTempDir=""

  echo "Package built: app-debian/build/${vPackageFinal}"
}

if ! fMain; then
  echo "error building the .deb package"
  exit 1
fi
