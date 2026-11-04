# PYMEHackers Control Center: referencia técnica

Este CODE también está disponible en:\
[en-GB](CODE.en-GB.md), [en-US](CODE.md), es-AR, [es-ES](CODE.es-ES.md)

Referencia técnica de PHCC, una aplicación de escritorio. Debian es la implementación disponible; macOS y Windows aún no están implementados. Las rutas de las tablas son relativas a `app-debian/`. Consulta el [manual de uso](MANUAL.es-AR.md).

## Índice

1. [Arquitectura y decisiones de diseño](#arquitectura-y-decisiones-de-diseño)
2. [Mapa de módulos](#mapa-de-módulos)
3. [Índice de símbolos clave](#índice-de-símbolos-clave)
4. [Flujos principales](#flujos-principales)
5. [Mapa de entradas y comandos](#mapa-de-entradas-y-comandos)
6. [Contrato de descubrimiento de módulos](#contrato-de-descubrimiento-de-módulos)
7. [Contrato del catálogo de módulos](#contrato-del-catálogo-de-módulos)
8. [Archivos de idioma](#archivos-de-idioma)
9. [Compilación y empaquetado](#compilación-y-empaquetado)
10. [Archivos instalados en el sistema](#archivos-instalados-en-el-sistema)
11. [Análisis de impacto](#análisis-de-impacto)
12. [Puntos de extensión](#puntos-de-extensión)
13. [Limitaciones conocidas](#limitaciones-conocidas)
14. [Estructura del proyecto](#estructura-del-proyecto)

## Arquitectura y decisiones de diseño

**El core es un menú, no un servicio.** Coloca un ícono en la barra superior cuyo menú tiene una cabecera, las dos secciones «Sistemas» (`sys`) y «Ciberseguridad» (`cs`), el submenú «Catálogo de módulos» y «Salir». No ejecuta ningún demonio propio. Los módulos son paquetes independientes con sus propios servicios, publicados en [PHCC-modules](https://github.com/pymehackers/PHCC-modules); siguen funcionando aunque el core no esté instalado o no esté en marcha, y el core se distribuye sin ningún módulo dentro (la compilación lo verifica).

**Dos frontends, un mismo comportamiento.** Los escritorios con bandeja StatusNotifier/AppIndicator (MATE, XFCE, Cinnamon, KDE, Unity...) usan el binario en C `phcc` (GTK 3 + libayatana-appindicator). GNOME Shell no tiene bandeja por defecto, así que el paquete incluye también la extensión nativa de GNOME Shell `phcc@pymehackers.com` (ESM, GNOME 45 a 50), con lo que no se depende de `gnome-shell-extension-appindicator`. Los dos frontends implementan el mismo menú, el mismo descubrimiento y la misma lógica de catálogo en dos lenguajes; cualquier cambio de comportamiento debe replicarse en `frontend/indicator.c` y en `frontend/gnome-extension/extension.js`.

**Un ícono, nunca dos.** La entrada de autoarranque del binario (`phcc.desktop`) lleva `NotShowIn=GNOME;`; el autoarranque exclusivo de GNOME (`phcc-gnome-activate.desktop`, `OnlyShowIn=GNOME;`) ejecuta `phcc-show --quiet`, que activa la extensión. El lanzador del menú de aplicaciones ejecuta `phcc-show`, que mira `XDG_CURRENT_DESKTOP`: en GNOME activa la extensión y en el resto arranca `phcc`, salvo que ya exista un proceso con ese nombre.

**Descubrimiento dinámico mediante manifiestos Desktop Entry.** El código nunca nombra ningún módulo. Cada módulo instala un manifiesto `.desktop` en `/usr/share/pymehackers/modules/<sección>/` y los frontends leen ese registro al construir el menú. Se eligió el formato Desktop Entry porque `GKeyFile` de GLib lo interpreta de forma nativa desde C y desde GJS, admite claves traducidas (`Name[es_AR]`) y ya define las Desktop Actions, que se corresponden una a una con el submenú de acciones de un módulo. Consultá el [Contrato de descubrimiento de módulos](#contrato-de-descubrimiento-de-módulos).

**Mínimo privilegio.** Los dos frontends se ejecutan con el usuario de la sesión. La única ruta de código con privilegios es `phcc-modules install|update|reinstall|uninstall`, lanzada mediante `pkexec`. La política de polkit fija la ruta exacta del programa (`org.freedesktop.policykit.exec.path` = `/usr/libexec/phcc/phcc-modules`) y exige autenticación de administrador (`auth_admin`, y `auth_admin_keep` en sesiones activas). Listar el catálogo nunca necesita root. El propietario, el nombre y la rama del repositorio son constantes del helper, de modo que ningún argumento puede hacer que una operación como root use otra fuente.

**Un protocolo de líneas entre el helper y los frontends.** `phcc-modules list` imprime un módulo por línea con 7 campos separados por tabuladores. Los frontends sólo parten líneas, lo que evita meter un parser de JSON en el código C para el catálogo. Todo el tratamiento del JSON de `module.json` se queda en el helper de bash (`jq`).

**Traducciones en JSON, con un pequeño parser en C.** Todos los textos visibles están en `frontend/lang/<idioma>.json`. GLib no tiene parser de JSON y los archivos son objetos planos, así que `frontend/i18n.c` contiene un parser estricto para exactamente esa forma, en lugar de agregar la dependencia `json-glib`; GJS usa `JSON.parse` y los scripts de shell usan `jq`. Los únicos textos que quedan fuera de los JSON son las claves `Name[xx]`/`Comment[xx]` de los archivos `.desktop` y los textos `xml:lang` de la política de polkit, porque el escritorio y polkit leen esos archivos directamente (excepción documentada en `RulesForThisProjectOnly.md`).

**Todo es asíncrono.** El listado del catálogo y las operaciones sobre módulos se ejecutan como procesos hijos `GSubprocess`/`Gio.Subprocess` con callbacks de finalización asíncronos, de modo que el panel nunca se bloquea. Cada proceso de frontend permite una sola operación sobre módulos a la vez (`vBusy`); es una marca por proceso, no un bloqueo de todo el sistema.

**Se compila en el destino, desde el código fuente.** No se distribuye ningún binario precompilado: el instalador de una línea descarga el tarball de `main` y compara su versión con la instalada; sólo cuando hay algo que compilar instala las dependencias de compilación, compila el `.deb` con `build/native/build.sh` y lo instala con `apt-get install --allow-downgrades`, así que siempre gana la versión del repositorio, aunque sea más antigua. El flujo de compilación cruzada para arm64 existe para quien quiera generar paquetes arm64 desde un equipo amd64.

**Sin ventanas.** El core sólo muestra menús y notificaciones, así que las reglas de ventanas de GNOME del proyecto no tienen dónde aplicarse.

## Mapa de módulos

| Módulo | Ruta | Responsabilidad | Depende de | Usado por |
|---|---|---|---|---|
| AppIndicator | [`frontend/indicator.c`](../app-debian/frontend/indicator.c) | Ícono y menú de la barra superior en escritorios con AppIndicator: secciones, acciones de módulos, catálogo, notificaciones | GTK 3, libayatana-appindicator3, `i18n.c`, registro, `phcc-modules` | Autoarranque `phcc.desktop`, `phcc-show` |
| Traducciones (C) | [`frontend/i18n.c`](../app-debian/frontend/i18n.c), [`frontend/i18n.h`](../app-debian/frontend/i18n.h) | Locale a idioma, cargador estricto de JSON plano, consultas `fT`/`fTf` con respaldo en en-US | GLib, `lang/*.json` | `indicator.c` |
| Extensión de GNOME Shell | [`frontend/gnome-extension/extension.js`](../app-debian/frontend/gnome-extension/extension.js) | Botón del panel y menú en GNOME Shell con las mismas funciones que el AppIndicator | GNOME Shell 45 a 50 (St, PanelMenu, PopupMenu, Gio), `lang/*.json`, registro, `phcc-modules` | GNOME Shell, `phcc-show` |
| Metadatos y estilo de la extensión | [`frontend/gnome-extension/metadata.json`](../app-debian/frontend/gnome-extension/metadata.json), [`stylesheet.css`](../app-debian/frontend/gnome-extension/stylesheet.css) | UUID, versiones de Shell admitidas, hoja de estilo de reserva | nada | GNOME Shell |
| Archivos de idioma | [`frontend/lang/`](../app-debian/frontend/lang/) | Todos los textos visibles en en-GB, en-US, es-AR y es-ES | nada | AppIndicator, extensión, `phcc-show` |
| Entradas de escritorio | [`frontend/desktop/`](../app-debian/frontend/desktop/) | Autoarranque del binario, autoarranque de GNOME, lanzador del menú de aplicaciones | `phcc`, `phcc-show` | Autoarranque de la sesión, menú de aplicaciones |
| Íconos | [`frontend/icons/`](../app-debian/frontend/icons/) | SVG en color (`phcc`), SVG simbólico (`phcc-symbolic`), PNG en color de 16 a 512 px | nada | AppIndicator, extensión, lanzadores, notificaciones, diálogo de polkit |
| Envoltorio de visualización | [`backend/phcc-show`](../app-debian/backend/phcc-show) | Muestra el ícono de la forma adecuada para el escritorio, de manera idempotente | bash, `jq`, `gnome-extensions`, `pgrep`, `setsid`, `notify-send` | Lanzador, autoarranque de GNOME |
| Helper del catálogo | [`backend/phcc-modules`](../app-debian/backend/phcc-modules) | Lista PHCC-modules y ejecuta el instalador de Debian de un módulo | bash, `curl`, `jq`, `dpkg`, `dpkg-query`, GitHub | AppIndicator, extensión, `pkexec` |
| Política de polkit | [`backend/polkit/com.pymehackers.phcc.modules.policy`](../app-debian/backend/polkit/com.pymehackers.phcc.modules.policy) | Autoriza a `pkexec` a ejecutar el helper como root | polkit | `pkexec` |
| Makefile | [`build/Makefile`](../app-debian/build/Makefile) | Compila `out/phcc`; objetivo `install` manual | `gcc`, `pkg-config`, bibliotecas -dev | `build-deb.sh`, `arm64-cross/build.sh` |
| Empaquetador | [`build/build-deb.sh`](../app-debian/build/build-deb.sh) | Prepara y genera el `.deb` para la arquitectura nativa | Makefile, `build/debian/`, `dpkg-deb` | `native/build.sh` |
| Metadatos del paquete | [`build/debian/control`](../app-debian/build/debian/control), [`postinst`](../app-debian/build/debian/postinst), [`postrm`](../app-debian/build/debian/postrm) | Versión, dependencias, pasos de posinstalación y de poseliminación | nada | `build-deb.sh`, `arm64-cross/build.sh`, `dpkg` |
| Flujo de compilación nativa | [`build/native/`](../app-debian/build/native/) | Dependencias de compilación, compilación, verificación, recogida en `dist/` | `build-deb.sh` | Instalador, desarrollo |
| Flujo de compilación cruzada arm64 | [`build/arm64-cross/`](../app-debian/build/arm64-cross/) | Toolchain multiarch, compilación cruzada, empaquetado, verificación | Makefile, `build/debian/`, `aarch64-linux-gnu-gcc` | Desarrollo |
| Instalador | [`build/install-update-reinstall-debian.sh`](../app-debian/build/install-update-reinstall-debian.sh) | Instalación, actualización, reinstalación y desinstalación en una línea, como root | `apt-get`, `curl`, tarball de GitHub, `native/build.sh` | Operación |
| Tests | [`tests/`](../app-debian/tests/) | Vacía: las reglas del proyecto prohíben escribir tests | nada | nada |

## Índice de símbolos clave

Sólo símbolos públicos o clave. Los números de línea salen de `grep -n` sobre el árbol actual.

| Símbolo | Archivo:línea | Qué hace |
|---|---|---|
| `cModulesRoot` | `frontend/indicator.c:26` | Raíz del registro, `/usr/share/pymehackers/modules` |
| `cModulesHelper` | `frontend/indicator.c:30` | Ruta del helper; debe coincidir con el `exec.path` de polkit |
| `aSections` | `frontend/indicator.c:42` | Identificadores de sección (`sys`, `cs`) y las claves de sus etiquetas |
| `CatalogEntry` | `frontend/indicator.c:56` | Una línea interpretada de `phcc-modules list` |
| `vCatalog` | `frontend/indicator.c:79` | Estado del catálogo (cargando/listo/fallido), entradas y marca de ocupado |
| `fNotify` | `frontend/indicator.c:86` | Notificación de escritorio con `notify-send` (sólo registro si falta) |
| `fOnActionActivate` | `frontend/indicator.c:113` | Ejecuta el `Exec` de una acción de módulo sin bloquear |
| `fBuildModuleActions` | `frontend/indicator.c:129` | Construye el submenú de acciones a partir de `Actions` y de `[Desktop Action ...]` |
| `fCompareModules` | `frontend/indicator.c:176` | Ordena los módulos por `X-PYMEHackers-Order` y después por nombre |
| `fBuildSectionMenu` | `frontend/indicator.c:188` | Lee una carpeta del registro y rellena el submenú de una sección |
| `fParseCatalog` | `frontend/indicator.c:277` | Interpreta las líneas de 7 campos del helper |
| `fOnCatalogListed` | `frontend/indicator.c:304` | Guarda el catálogo listado y reconstruye el menú |
| `fLoadCatalog` | `frontend/indicator.c:330` | Lanza `phcc-modules list --lang X [--refresh]` de forma asíncrona |
| `fOnOperationFinished` | `frontend/indicator.c:383` | Convierte el código de salida en una notificación y recarga el catálogo |
| `fOnCatalogActionActivate` | `frontend/indicator.c:410` | Lanza `pkexec phcc-modules <acción> <id>` |
| `fBuildCatalogMenu` | `frontend/indicator.c:463` | Construye el submenú «Catálogo de módulos» según el estado actual |
| `fBuildMenu` | `frontend/indicator.c:543` | Construye el menú raíz completo |
| `fRefreshMenu` | `frontend/indicator.c:580` | Reconstruye el menú y se lo entrega al indicador |
| `main` | `frontend/indicator.c:586` | Inicializa GTK y las traducciones, crea el indicador y carga el catálogo |
| `cDefaultLangDir` | `frontend/i18n.h:15` | `/usr/share/pymehackers/core/lang` (lo sustituye `PHCC_LANG_DIR`) |
| `aSupportedLanguages` | `frontend/i18n.c:14` | en-GB, en-US, es-AR, es-ES |
| `fParseObject` | `frontend/i18n.c:118` | Parser estricto de un objeto JSON plano de cadenas |
| `fMatchLanguage` | `frontend/i18n.c:198` | Nombre de locale a idioma admitido |
| `fI18nInit` | `frontend/i18n.c:225` | Resuelve el idioma y lo carga junto con el respaldo en-US |
| `fI18nLanguage` | `frontend/i18n.c:247` | Idioma seleccionado (se pasa al helper como `--lang`) |
| `fT` | `frontend/i18n.c:251` | Texto de una clave (idioma elegido, después en-US, después la propia clave) |
| `fTf` | `frontend/i18n.c:260` | `fT` con los marcadores `{0}`, `{1}`... |
| `cModulesHelper` | `frontend/gnome-extension/extension.js:39` | Ruta del helper que usa la extensión |
| `cUuid` | `frontend/gnome-extension/extension.js:46` | `phcc@pymehackers.com`, lo usa «Salir» |
| `fMatchLanguage` | `frontend/gnome-extension/extension.js:55` | Misma resolución de idioma que `i18n.c` |
| `Translator` | `frontend/gnome-extension/extension.js:83` | Carga el idioma elegido y el respaldo en-US; `mT` en la línea 98 |
| `PymeHackersIndicator` | `frontend/gnome-extension/extension.js:107` | Subclase de `PanelMenu.Button`; `_init` en la línea 110 |
| `mBuildMenu` | `frontend/gnome-extension/extension.js:141` | Cabecera, secciones, catálogo y «Salir» |
| `mDiscoverModules` | `frontend/gnome-extension/extension.js:194` | Lee una carpeta del registro y ordena los módulos |
| `mParseManifest` | `frontend/gnome-extension/extension.js:232` | Lee `Name`, `X-PYMEHackers-Order` y las acciones de un manifiesto |
| `mLoadCatalog` | `frontend/gnome-extension/extension.js:280` | Ejecuta `phcc-modules list` de forma asíncrona |
| `mParseCatalog` | `frontend/gnome-extension/extension.js:319` | Interpreta las líneas de 7 campos |
| `mBuildCatalog` | `frontend/gnome-extension/extension.js:347` | Rellena el submenú «Catálogo de módulos» |
| `mRunOperation` | `frontend/gnome-extension/extension.js:407` | Ejecuta `pkexec phcc-modules <acción> <id>` y notifica |
| `mQuit` | `frontend/gnome-extension/extension.js:461` | Oculta el ícono con `gnome-extensions disable` |
| `PymeHackersExtension.enable` / `disable` | `frontend/gnome-extension/extension.js:472` / `478` | Agrega o destruye el indicador del panel |
| `fIsGnome` | `backend/phcc-show:106` | `XDG_CURRENT_DESKTOP` contiene `GNOME` |
| `fEnableOnGnome` | `backend/phcc-show:114` | Espera a que el Shell conozca la extensión y la activa |
| `fLaunchBinary` | `backend/phcc-show:160` | Arranca `phcc` con `setsid -f` salvo que `pgrep -u <uid> -x phcc` encuentre uno del mismo usuario |
| `fMain` | `backend/phcc-show:178` | Interpreta `--quiet`/`--help` y elige el camino |
| `cApiUrl`, `cRawUrl`, `cInstallerPath` | `backend/phcc-modules:31`, `32`, `33` | URL fijas del repositorio y ruta del instalador |
| `cLogFile` | `backend/phcc-modules:34` | `/var/log/phcc-modules.log` |
| `cIdPattern`, `cPackagePattern` | `backend/phcc-modules:36`, `37` | Validación de identificadores de módulo y nombres de paquete |
| `fLog` | `backend/phcc-modules:62` | stderr y, como root, el registro con marca de tiempo UTC |
| `fNormalizeLanguage` | `backend/phcc-modules:71` | Locale o etiqueta a idioma admitido |
| `fPlatform` | `backend/phcc-modules:111` | `debian-$(dpkg --print-architecture)` |
| `fInstalledVersion` | `backend/phcc-modules:120` | Versión instalada de un paquete (sólo estado `ii`) |
| `fDownloadCatalog` | `backend/phcc-modules:131` | Listado de GitHub, descarga y validación de cada `module.json` |
| `fCatalogFile` | `backend/phcc-modules:188` | Caché de 10 minutos por usuario; root siempre descarga |
| `fList` | `backend/phcc-modules:229` | Comando `list`: imprime las líneas de 7 campos |
| `fRunOperation` | `backend/phcc-modules:267` | Operación como root: comprueba, descarga y ejecuta el instalador del módulo |
| `fMain` | `backend/phcc-modules:344` | Interpretación de la línea de comandos |
| `com.pymehackers.phcc.modules` | `backend/polkit/com.pymehackers.phcc.modules.policy:16` | Acción de polkit; `exec.path` en la línea 32 |
| `all`, `install`, `clean` | `build/Makefile:46`, `52`, `69` | Objetivos de make |
| `fMain` | `build/build-deb.sh:27` | Empaquetador `.deb` nativo |
| `fVerify` | `build/native/build.sh:123` | Rutas obligatorias y blindaje «core sin módulos» |
| `fCollectArtifact` | `build/native/build.sh:216` | Copia atómica en `native/dist/` |
| `fCompile` | `build/arm64-cross/build.sh:115` | Compilación cruzada y comprobación de la arquitectura ELF |
| `fPackage` | `build/arm64-cross/build.sh:137` | Prepara y genera el `.deb` arm64 |
| `fVerify` | `build/arm64-cross/build.sh:280` | El mismo blindaje que el flujo nativo |
| `fStartLog` | `build/install-update-reinstall-debian.sh:50` | Copia toda la salida en `/root/phcc-install.log` (modo 600) |
| `fDownloadSource` | `build/install-update-reinstall-debian.sh:116` | Descarga y extrae el tarball de `main` |
| `fBuildAndInstall` | `build/install-update-reinstall-debian.sh:143` | Comprobación de versión, dependencias de compilación (sólo si hay que compilar), compilación, `apt-get install -y --allow-downgrades` |
| `fUninstall` | `build/install-update-reinstall-debian.sh:89` | `apt-get remove phcc` |
| `fMain` | `build/debian/postinst:11` | Carpetas del registro, archivo de registro, cachés de escritorio e íconos |
| `fMain` | `build/debian/postrm:11` | Con `purge`: carpetas vacías del registro y el archivo de registro |

## Flujos principales

### Inicio de sesión en escritorios con AppIndicator

```text
/etc/xdg/autostart/phcc.desktop (Exec=phcc, NotShowIn=GNOME)
  └─ main                                  indicator.c:586
      ├─ gtk_init, fI18nInit
      ├─ g_object_new(APP_INDICATOR_TYPE, id=phcc, icon-name=phcc)
      └─ fLoadCatalog(FALSE)
          ├─ g_subprocess_new(phcc-modules list --lang <idioma>)
          ├─ fRefreshMenu ─ fBuildMenu ─┬─ fBuildSectionMenu(sys), fBuildSectionMenu(cs)
          │                             └─ fBuildCatalogMenu   (clave catalog.loading)
          └─ (asíncrono) fOnCatalogListed ─ fParseCatalog ─ fRefreshMenu
```

### Inicio de sesión en GNOME Shell

```text
/etc/xdg/autostart/phcc-gnome-activate.desktop (Exec=phcc-show --quiet, OnlyShowIn=GNOME)
  └─ phcc-show fMain ─ fIsGnome ─ fEnableOnGnome
      ├─ gnome-extensions info phcc@pymehackers.com   (hasta 10 intentos, 1 s entre ellos)
      ├─ gnome-extensions list --enabled              (ya activada: fin)
      └─ gnome-extensions enable phcc@pymehackers.com
GNOME Shell ─ PymeHackersExtension.enable ─ new PymeHackersIndicator
  └─ _init ─ Translator ─ mBuildMenu ─ mLoadCatalog(false)
      └─ (asíncrono) mParseCatalog ─ mRebuildMenu
```

### Lanzador del menú de aplicaciones

```text
pymehackers-control-center.desktop (Exec=phcc-show)
  └─ phcc-show fMain
      ├─ GNOME:  fEnableOnGnome (1 intento, con notificaciones)
      └─ resto:  fLaunchBinary ─ pgrep -u $(id -u) -x phcc ─ setsid -f phcc
```

### Acción de un módulo

```text
elemento del menú ─ fOnActionActivate (C) | mSpawn (JS)
  └─ g_spawn_command_line_async(<Exec de la Desktop Action>)   (usuario de la sesión, sin shell)
```

### Operación del catálogo (install, update, reinstall, uninstall)

```text
elemento del menú ─ fOnCatalogActionActivate (C) | mRunOperation (JS)
  ├─ notificación "notify.<acción>"
  └─ pkexec /usr/libexec/phcc/phcc-modules <acción> <id>
      └─ acción de polkit com.pymehackers.phcc.modules (auth_admin_keep)
          └─ fMain ─ fRunOperation
              ├─ fPlatform, fCatalogFile(1) ─ fDownloadCatalog (recién descargado, sin caché)
              ├─ jq: el módulo existe y admite la plataforma
              ├─ curl <raw>/<id>/app-debian/build/install-update-reinstall-debian.sh
              ├─ los dos primeros bytes deben ser "#!"
              └─ bash instalador [--reinstall|--uninstall] < /dev/null >> /var/log/phcc-modules.log
  (asíncrono) fOnOperationFinished (C) | callback de wait_async (JS)
      ├─ salida 0: notify.done, 126: notify.cancelled, 127: notify.denied, otra: notify.failed
      └─ fLoadCatalog(TRUE) | mLoadCatalog(true) ─ menú reconstruido (secciones redescubiertas)
```

### Listado del catálogo dentro del helper

```text
phcc-modules list [--lang L] [--refresh]
  └─ fMain ─ fNormalizeLanguage | fSessionLanguage ─ fList
      ├─ fPlatform
      ├─ fCatalogFile(refresh)
      │   ├─ acierto de caché (< 600 s): ~/.cache/phcc/catalog.json
      │   └─ fDownloadCatalog: API de contenidos de GitHub ─ module.json de cada carpeta ─ validación jq ─ jq -s
      └─ proyección jq ─ fInstalledVersion(paquete) ─ printf de 7 campos separados por tabuladores
```

### Instalación de una línea

```text
curl ... | bash
  └─ fMain ─ fCheckSystem ─ fStartLog
      ─ fDownloadSource (tarball de main en codeload) ─ fBuildAndInstall
          ├─ fRepositoryVersion frente a fInstalledVersion (iguales y sin --reinstall: fin)
          ├─ fInstallDependencies (apt-get update/install, sólo si hay que compilar)
          ├─ native/build.sh ─ fCheckDependencies ─ fBuildAndPackage
          │   └─ build-deb.sh ─ make all ─ staging ─ dpkg-deb --root-owner-group --build
          │   ─ fVerify ─ fCollectArtifact (native/dist/)
          └─ apt-get install -y --allow-downgrades [--reinstall] native/dist/phcc_<versión>_<arq>.deb ─ postinst
```

### Compilación cruzada arm64

```text
arm64-cross/build.sh ─ fCheckEnvironment ─ fCheckDependencies ─ fReadVersion
  ─ fCompile (make -C build all CC=aarch64-linux-gnu-gcc BUILDDIR=out-arm64, file -b = aarch64)
  ─ fPackage (staging, Architecture del control de amd64 a arm64, dpkg-deb)
  ─ fVerify ─ fCollectArtifact (arm64-cross/dist/)
```

## Mapa de entradas y comandos

### Programas, entradas de escritorio y extensión

| Ruta/comando | Manejador | Archivo |
|---|---|---|
| `phcc` | `main` | `frontend/indicator.c` |
| `phcc-show` | `fMain` (modo manual, con notificaciones) | `backend/phcc-show` |
| `phcc-show --quiet` | `fMain` (sin notificaciones, 10 intentos) | `backend/phcc-show` |
| `phcc-show --help` | `fMain` (imprime `Usage: phcc-show [--quiet]`) | `backend/phcc-show` |
| `/usr/libexec/phcc/phcc-modules list [--lang LANG] [--refresh]` | `fList` | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules install ID` / `update ID` | `fRunOperation` (instalador sin argumentos) | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules reinstall ID` | `fRunOperation` (`--reinstall`) | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules uninstall ID` | `fRunOperation` (`--uninstall`) | `backend/phcc-modules` |
| `/usr/libexec/phcc/phcc-modules -h` / `--help` | `fShowUsage` | `backend/phcc-modules` |
| `pkexec /usr/libexec/phcc/phcc-modules ...` | acción de polkit `com.pymehackers.phcc.modules` | `backend/polkit/com.pymehackers.phcc.modules.policy` |
| `/etc/xdg/autostart/phcc.desktop` | `Exec=phcc`, `NotShowIn=GNOME;`, retardo de 3 s en MATE | `frontend/desktop/phcc.desktop` |
| `/etc/xdg/autostart/phcc-gnome-activate.desktop` | `Exec=phcc-show --quiet`, `OnlyShowIn=GNOME;`, retardo de 5 s | `frontend/desktop/phcc-gnome-activate.desktop` |
| `/usr/share/applications/pymehackers-control-center.desktop` | `Exec=phcc-show` | `frontend/desktop/pymehackers-control-center.desktop` |
| Extensión de GNOME `phcc@pymehackers.com` | `PymeHackersExtension.enable` / `disable` | `frontend/gnome-extension/extension.js` |

Códigos de salida del helper: `0` éxito, `1` cualquier fallo. Los errores de uso devuelven `2` dentro de `fMain`, pero el envoltorio obligatorio `if ! fMain` convierte cualquier fallo en `1`. `pkexec` devuelve `126` (diálogo cerrado) o `127` (no autorizado, sin agente de autenticación o error); los frontends muestran «notify.cancelled» con `126` y «notify.denied» con `127`.

Variables de entorno que lee el código: `PHCC_LANG_DIR` (sólo el indicador en C), `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG` (idioma, todos los componentes), `XDG_CURRENT_DESKTOP` (`phcc-show`), `XDG_CACHE_HOME` y `HOME` (caché del helper), `DESTDIR` y `PREFIX` (Makefile).

### Scripts de compilación e instalación

| Ruta/comando | Manejador | Archivo |
|---|---|---|
| `make -C app-debian/build` (`all`) | genera `out/phcc` | `build/Makefile` |
| `make -C app-debian/build all CC=... BUILDDIR=...` | variables que usa el flujo arm64 | `build/Makefile` |
| `make -C app-debian/build install [DESTDIR=...] [PREFIX=/usr]` | copia los archivos, sin scripts de mantenimiento | `build/Makefile` |
| `make -C app-debian/build clean` | borra `out/` | `build/Makefile` |
| `app-debian/build/build-deb.sh` | `fMain`, genera `out/phcc_<versión>_<arq>.deb` | `build/build-deb.sh` |
| `app-debian/build/native/build.sh [--clean] [--install-deps] [--help]` | `fMain`, deja el resultado en `native/dist/` | `build/native/build.sh` |
| `app-debian/build/native/install-build-dependencies.sh` | `fMain` | `build/native/install-build-dependencies.sh` |
| `app-debian/build/arm64-cross/build.sh [--install-deps] [--clean] [--help]` | `fMain`, deja el resultado en `arm64-cross/dist/` | `build/arm64-cross/build.sh` |
| `app-debian/build/arm64-cross/install-build-dependencies.sh` | `fMain` | `build/arm64-cross/install-build-dependencies.sh` |
| `install-update-reinstall-debian.sh` | instalar o actualizar | `build/install-update-reinstall-debian.sh` |
| `install-update-reinstall-debian.sh --reinstall` | compilar y reinstalar la misma versión | `build/install-update-reinstall-debian.sh` |
| `install-update-reinstall-debian.sh --uninstall` | `apt-get remove phcc` | `build/install-update-reinstall-debian.sh` |
| `install-update-reinstall-debian.sh --help` | `fShowHelp` | `build/install-update-reinstall-debian.sh` |
| `postinst` (cualquier argumento) | `fMain` | `build/debian/postinst` |
| `postrm purge` | `fMain` (limpieza sólo con `purge`) | `build/debian/postrm` |

## Contrato de descubrimiento de módulos

Esto es lo que un módulo debe hacer en Debian para aparecer en «Sistemas» o en «Ciberseguridad». Lo implementan los dos frontends (`fBuildSectionMenu`/`fBuildModuleActions` en C, `mDiscoverModules`/`mParseManifest` en JS).

- **Ubicación.** Un archivo terminado en `.desktop` dentro de `/usr/share/pymehackers/modules/sys/` o de `/usr/share/pymehackers/modules/cs/`. La carpeta decide la sección; el core ignora cualquier clave `X-PYMEHackers-Section`.
- **`Name` de `[Desktop Entry]`** (obligatoria). Etiqueta visible del módulo. Se respetan las claves traducidas (`Name[es_AR]`, `Name[es]`...) según las reglas de locale de GLib. Un manifiesto sin `Name`, o que `GKeyFile` no pueda interpretar, se descarta.
- **`X-PYMEHackers-Order`** (entero opcional). Los valores menores aparecen antes; si falta o no es válido vale `1000`. Los empates se ordenan por nombre (orden de bytes en C, `localeCompare` en JS).
- **`Actions`** (opcional). Identificadores de acción separados por punto y coma. Cada identificador necesita un grupo `[Desktop Action <id>]` con `Name` (traducible) y `Exec`; una acción a la que le falte alguna de las dos claves se descarta. Un módulo sin clave `Actions` se muestra como un elemento simple, sin submenú; la extensión de GNOME también lo hace cuando ninguna de sus acciones es válida.
- **`Exec`.** Se ejecuta con el usuario de la sesión mediante `g_spawn_command_line_async` (C) o `GLib.spawn_command_line_async` (JS): las comillas siguen las reglas de la shell, pero no hay shell, así que no funcionan tuberías, redirecciones, variables ni códigos de campo como `%f`. Una acción que necesite root debe llamar ella misma a `pkexec`.
- **Claves ignoradas.** `Icon`, `Comment`, `X-PYMEHackers-Section`, `X-PYMEHackers-Service` y cualquier otra clave pueden existir para uso propio del módulo; el core no las lee.
- **Actualización.** No hay vigilancia de archivos. El menú se reconstruye al arrancar y después de cada listado del catálogo (arranque, «Actualizar el catálogo», final de una operación del catálogo). Un manifiesto instalado desde una terminal aparece tras «Actualizar el catálogo» o tras reiniciar el frontend.

Ejemplo de manifiesto (`/usr/share/pymehackers/modules/cs/example.desktop`):

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

## Contrato del catálogo de módulos

El contrato se comparte con PHCC-modules y está recogido en el `RulesForThisProjectOnly.md` de los dos proyectos. La parte de Debian la implementa `backend/phcc-modules`.

**Repositorio.** `https://github.com/pymehackers/PHCC-modules`, rama `main` (`backend/phcc-modules:28-33`). No se puede cambiar en tiempo de ejecución, a propósito.

**Qué es un módulo.** Cualquier carpeta de la raíz, listada mediante `https://api.github.com/repos/pymehackers/PHCC-modules/contents?ref=main` con `type == "dir"`, cuyo nombre cumpla `^[a-z0-9][a-z0-9-]{0,62}$` y cuyo `module.json` pueda descargarse de `https://raw.githubusercontent.com/pymehackers/PHCC-modules/main/<id>/module.json`. Las carpetas sin `module.json` (por ejemplo `_` o `doc`) se saltan sin aviso; un `module.json` no válido se salta y se registra como `ignoring <id>: its module.json is not valid`.

**`module.json` tal y como se valida en Debian (`jq`).**

| Campo | Regla en el helper | Uso |
|---|---|---|
| `id` | debe ser igual al nombre de la carpeta | Argumento de las operaciones |
| `section` | `sys` o `cs` | Orden (Sistemas primero) |
| `version` | cadena | Se muestra y se compara con la versión instalada |
| `package` | cadena que cumple `^[a-z0-9][a-z0-9+.-]+$` | Consulta con `dpkg-query` de la versión instalada |
| `name`, `description` | objetos con las claves `en-GB`, `en-US`, `es-AR`, `es-ES` | Idioma elegido, después `en-US`, después el id (nombre) o vacío (descripción) |
| `platforms` | lista o ausente | Debe contener `debian-amd64` / `debian-arm64` para estar admitido; si falta, no se admite en ninguna plataforma |

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

**Identificador de plataforma.** `debian-` seguido de `dpkg --print-architecture` (`debian-amd64` y `debian-arm64`; ninguna otra arquitectura aparece hoy en `platforms`, así que en ellas todos los módulos se muestran como no admitidos).

**Versión instalada.** `dpkg-query -W -f='${db:Status-Abbrev}|${Version}' <paquete>`; sólo cuenta como instalado el estado `ii`.

**Salida de `list`.** Una línea por cada módulo válido, con 7 campos separados por tabuladores: `id`, `section`, `version`, versión instalada (vacía si no está instalado), admitido (`0`/`1`), nombre y descripción. Los tabuladores, CR, LF y `0x1F` de los textos se sustituyen por espacios. Los frontends ordenan Sistemas antes que Ciberseguridad y después por nombre, e ignoran las líneas que no tengan 7 campos, id o nombre.

**Operaciones.** `install` y `update` ejecutan el instalador sin argumentos, `reinstall` agrega `--reinstall` y `uninstall` agrega `--uninstall`. El helper se niega a continuar salvo que sea root, el id sea válido, el módulo esté en un catálogo recién descargado y su `platforms` incluya la plataforma actual. El instalador es `<id>/app-debian/build/install-update-reinstall-debian.sh`, descargado de `raw.githubusercontent.com`; sus dos primeros bytes deben ser `#!`. Se ejecuta como `bash <instalador> [argumento] < /dev/null >> /var/log/phcc-modules.log 2>&1`, así que debe ser idempotente y no interactivo, debe salir con `0` si todo va bien, debe instalar el manifiesto del módulo en el registro y debe quitarlo con `--uninstall`.

**Detección de actualizaciones.** Los frontends ofrecen «Actualizar a <versión>» cuando la cadena de la versión instalada es distinta de la versión del catálogo. Es una comparación de cadenas, no el orden de versiones de dpkg.

**Caché.** `${XDG_CACHE_HOME:-$HOME/.cache}/phcc/catalog.json` por usuario, válida durante 600 segundos; `--refresh` («Actualizar el catálogo») la salta. Root nunca usa caché.

**Red.** `curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 --retry 2`. La API de GitHub se usa sin autenticar (GitHub permite 60 solicitudes por hora y dirección IP); cada descarga del catálogo cuesta una solicitud a la API más una descarga raw por carpeta.

**Registro.** `/var/log/phcc-modules.log`, modo `0640`, lo crea `postinst` o la primera operación. `fLog` sólo escribe líneas cuando se ejecuta como root, con la marca de tiempo UTC nativa, por ejemplo `2026-10-29@13-59-59.723 install example: started`. La salida del instalador del módulo se agrega tal cual, sin marcas de tiempo.

**Modelo de confianza.** La integridad descansa en HTTPS hacia GitHub, en el repositorio fijo y en la autenticación de polkit. No hay firmas: quien pueda publicar en `main` de PHCC-modules puede ejecutar código como root en cualquier equipo donde un administrador autorice una operación.

## Archivos de idioma

- Fuente: `frontend/lang/{en-GB,en-US,es-AR,es-ES}.json`. Instalados en `/usr/share/pymehackers/core/lang/`. Objetos JSON planos de claves y valores de tipo cadena; `{0}`, `{1}`... son marcadores.
- Consulta: idioma elegido, después `en-US`, después la propia clave (una clave que falte se ve como su nombre).
- Resolución del idioma (idéntica en `i18n.c:198`, `extension.js:55`, `phcc-show:35` y `phcc-modules:71`): la primera entrada de `LANGUAGE` (lista separada por dos puntos), `LC_ALL`, `LC_MESSAGES`, `LANG` que encaje. Se descartan la codificación y el modificador (`es_AR.UTF-8` pasa a `es-AR`); gana la coincidencia exacta; si no, `en`/`en-*` se asigna a `en-US` y `es`/`es-*` a `es-ES`; cualquier otra cosa (`C`, `fr_FR`...) da `en-US`. Los frontends en C y JS usan `g_get_language_names()`, que sigue las mismas variables.

| Claves | Las usa |
|---|---|
| `app.title` | Título del indicador y notificaciones (C), cabecera del menú y notificaciones (JS), notificaciones de `phcc-show` |
| `menu.header` | Sólo la cabecera del menú del AppIndicator |
| `menu.catalog`, `menu.quit`, `section.*` | Los dos frontends |
| `catalog.*`, `action.*`, `notify.*` (incluida `notify.denied`), `error.spawn` | Los dos frontends |
| `error.registry`, `error.quit` | Sólo la extensión de GNOME |
| `show.*` | `phcc-show` |

Textos que no salen de estos archivos: nombres y acciones de los módulos (manifiesto del módulo), nombres y descripciones del catálogo (`module.json`), los lanzadores `.desktop` y el diálogo de polkit (traducidos dentro de esos archivos).

## Compilación y empaquetado

- **Opciones del compilador** (`build/Makefile`): `-std=c11 -O2 -Wall -Wextra -D_GNU_SOURCE` más `pkg-config --cflags/--libs gtk+-3.0 ayatana-appindicator3-0.1`. Las recetas usan `.RECIPEPREFIX := >` para que el Makefile no contenga tabuladores (regla de indentación del proyecto).
- **`build-deb.sh`**: lee `Version` de `build/debian/control` y la arquitectura de `dpkg --print-architecture`, ejecuta `make all`, prepara el árbol en una carpeta de `mktemp -d` con modos explícitos, reescribe `Architecture`, comprueba las piezas obligatorias, genera el paquete con `dpkg-deb --root-owner-group --build` en una carpeta temporal dentro de `out/`, comprueba `Package`, `Version` y `Architecture` y mueve el resultado a `out/phcc_<versión>_<arq>.deb`.
- **`native/build.sh`**: comprueba `gtk+-3.0`, `ayatana-appindicator3-0.1`, `gcc`, `make`, `dpkg-deb` y `pkg-config`; ejecuta `build-deb.sh`; `fVerify` lista el paquete (`dpkg-deb --info`, `--contents`), exige todas las rutas obligatorias y aplica el **blindaje «core sin módulos»**: falla si el paquete contiene algo que encaje con `./usr/share/pymehackers/modules/(sys|cs)/.+`, `phcc-mod-` o `./etc/pymehackers/`. El `.deb` verificado se copia en `native/dist/` de forma atómica (archivo temporal, `cmp`, `chmod 0644`, `mv`).
- **`arm64-cross/build.sh`**: usa multiarch (`dpkg --add-architecture arm64`), `PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig` y `PKG_CONFIG_SYSROOT_DIR=/`, compila en `build/out-arm64/`, exige que `file -b` informe de `aarch64` (su script de dependencias instala y comprueba `file`), prepara su propio árbol de paquete (una copia de la lógica de `build-deb.sh`), reescribe `Architecture: amd64` como `arm64`, aplica el mismo blindaje y recoge el resultado en `arm64-cross/dist/`. Si una fuente de apt de terceros no sirve arm64, `apt-get update` falla: hay que restringir esa fuente con `Architectures: amd64`.
- **Scripts de dependencias**: instalan con `apt-get` como root, o mediante `sudo` cuando los ejecuta otro usuario; leen de `/dev/tty`, así que necesitan una terminal. No hacen nada si `pkg-config` ya encuentra las bibliotecas.
- **Plantilla de los scripts**: todos los scripts de bash usan `set -euo pipefail`, `fCleanup` + `trap fCleanup EXIT` e `if ! fMain`. Como Bash ignora `set -e` dentro del operando de `!`, cada paso crítico se comprueba de forma explícita.
- **Artefactos** (`out/`, `out-arm64/`, `native/dist/`, `arm64-cross/dist/`): los ignora `.gitignore`.
- **Sistemas de archivos de red o FUSE** (sshfs): `install -m` no siempre puede fijar permisos ahí; hay que compilar desde una copia en un disco local.

## Archivos instalados en el sistema

Los instala el paquete `phcc` (propietario `root:root`, `dpkg-deb --root-owner-group`):

| Ruta | Modo | Origen |
|---|---|---|
| `/usr/bin/phcc` | 0755 | `build/out/phcc` (o `out-arm64/phcc`) |
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
| `/usr/share/pymehackers/modules/sys/`, `/usr/share/pymehackers/modules/cs/` | 0755 (carpetas vacías) | las crea el empaquetador |
| `DEBIAN/control` | 0644 | `build/debian/control` (con `Architecture` reescrito) |
| `DEBIAN/postinst`, `DEBIAN/postrm` | 0755 | `build/debian/` |

El paquete no declara `conffiles`, así que los cambios locales en los archivos de `/etc/xdg/autostart/` se sobrescriben al actualizar (los ajustes por usuario en `~/.config/autostart/` no).

Creados fuera del paquete:

| Ruta | Modo | Lo crea |
|---|---|---|
| `/var/log/phcc-modules.log` | 0640 | `postinst`, o la primera operación del helper; se borra con `purge` |
| `/root/phcc-install.log` | 0600 | `install-update-reinstall-debian.sh` (se agrega en cada ejecución) |
| `${XDG_CACHE_HOME:-~/.cache}/phcc/catalog.json` | el del usuario | `phcc-modules list` ejecutado por cada usuario |
| Carpetas temporales de `mktemp -d` | el del usuario | helper y scripts; las borra `fCleanup` |

## Análisis de impacto

| Si cambiás... | Actualizá también |
|---|---|
| La ruta del registro (`cModulesRoot`) | `indicator.c:26`, `extension.js:31`, el objetivo `install` del `Makefile`, `build-deb.sh`, `arm64-cross/build.sh`, los patrones de verificación de `native/build.sh` y `arm64-cross/build.sh`, `postinst`, `postrm`, todos los instaladores de módulos de PHCC-modules y el contrato de `RulesForThisProjectOnly.md` |
| La ruta del helper (`cModulesHelper`) | `indicator.c:30`, `extension.js:39`, el `exec.path` de polkit, el `Makefile`, los dos empaquetadores y las dos listas de verificación |
| El formato de salida de `phcc-modules list` | `fParseCatalog`, `mParseCatalog` |
| Las reglas de `module.json` o la ruta del instalador | `fDownloadCatalog`, `fList`, `fRunOperation`, el `RulesForThisProjectOnly.md` de PHCC y de PHCC-modules y todos los módulos |
| Los identificadores de sección | `aSections` en C y JS, las claves `section.*`, la validación del helper (`sys`/`cs`), las carpetas del registro en los empaquetadores, `postinst`, `postrm`, los patrones de verificación |
| Un texto visible | Los cuatro archivos `frontend/lang/*.json` (una clave que falte en un idioma cae en en-US) |
| Los idiomas admitidos | `aSupportedLanguages` (`i18n.c`, `extension.js`), `aLanguages` (`phcc-show`, `phcc-modules`), `LANGS` (`Makefile`), los bucles de idiomas de los dos empaquetadores y de las dos listas de verificación, las traducciones de los `.desktop` y de polkit, y el contrato de `module.json` |
| La lista de archivos del paquete | El objetivo `install` del `Makefile`, `build-deb.sh`, `fPackage` de `arm64-cross/build.sh`, `fVerify` en los dos flujos y la sección [Archivos instalados en el sistema](#archivos-instalados-en-el-sistema) |
| La versión del paquete | Sólo `Version` en `build/debian/control` (la leen el instalador y los dos flujos) |
| El UUID de la extensión | `metadata.json`, `cUuid` en `extension.js` y en `phcc-show`, `EXTUUID` en el `Makefile`, los dos empaquetadores y listas de verificación, y el comentario de `phcc.desktop` |
| Las versiones de GNOME Shell admitidas | `shell-version` en `metadata.json` (probar antes: la extensión usa la API ESM de la versión 45 en adelante) |
| Las dependencias de ejecución | `Depends`/`Recommends` en `build/debian/control`; las de compilación en `aBuildPackages` (instalador) y `cAptPackages` (scripts de dependencias) |
| La acción o los valores por defecto de polkit | Sólo el archivo de la política (`pkexec` elige la acción por `exec.path`) |

## Puntos de extensión

- **Agregar un módulo.** No cambia nada en el core: crear el módulo en PHCC-modules con `module.json`, el instalador de Debian y el manifiesto descrito en el [Contrato de descubrimiento de módulos](#contrato-de-descubrimiento-de-módulos).
- **Agregar una acción a un módulo.** Editar sólo el manifiesto del módulo (`Actions` y un grupo `[Desktop Action ...]` más).
- **Agregar un texto visible.** Agregar la clave a los cuatro archivos `frontend/lang/*.json` y leerla con `fT`/`fTf` (C), `this.mT` (JS) o `fT` (`phcc-show`).
- **Agregar un idioma.** Agregar `frontend/lang/<xx-YY>.json` y actualizar todos los puntos de la fila «Los idiomas admitidos» del [Análisis de impacto](#análisis-de-impacto).
- **Agregar una sección.** Agregarla a `aSections` (C y JS), agregar `section.<id>` a todos los archivos de idioma, aceptarla en el helper, crear la carpeta del registro en los empaquetadores, en `postinst` y en `postrm`, ampliar los patrones de verificación, y actualizar el contrato en los dos proyectos.
- **Agregar una operación al catálogo.** Agregar el caso en `fRunOperation` y en `fMain` del helper, el elemento de menú en `fBuildCatalogMenu` y en `mBuildCatalog`, las claves `action.<nombre>` y `notify.<nombre>` y el argumento del instalador en el contrato de PHCC-modules.
- **Agregar una arquitectura** (por ejemplo `armhf`). Un flujo cruzado nuevo como `build/arm64-cross/` y un identificador de plataforma `debian-<arq>` nuevo en el contrato de `module.json`.
- **Ejecutar el indicador desde el árbol de código.** `make -C app-debian/build && PHCC_LANG_DIR=app-debian/frontend/lang app-debian/build/out/phcc`. El catálogo sigue necesitando el helper instalado en `/usr/libexec/phcc/phcc-modules`, y la extensión siempre lee `/usr/share/pymehackers/core/lang/`.

## Limitaciones conocidas

- El menú no vigila el registro: un módulo instalado fuera del catálogo aparece tras «Actualizar el catálogo» o tras un reinicio.
- `vBusy` sólo serializa las operaciones dentro de un proceso de frontend; dos usuarios o una terminal pueden ejecutar el helper a la vez (el bloqueo propio de apt sigue serializando las operaciones de paquetes).
- `uninstall` desde el catálogo necesita que el módulo siga en el repositorio y que incluya la plataforma actual; si no, hay que usar el instalador del propio módulo con `--uninstall`.
- Los instaladores y los `module.json` no están firmados (consultá el modelo de confianza más arriba).
- La extensión requiere GNOME Shell 45 o posterior. Los escritorios cuyo `XDG_CURRENT_DESKTOP` contiene `GNOME` sin ejecutar GNOME Shell (por ejemplo Budgie o GNOME Flashback) no reciben ni la extensión ni el autoarranque del AppIndicator.
- `/var/log/phcc-modules.log` sólo lo puede leer root, aunque la notificación de fallo remite al usuario a ese archivo.
- La cabecera del menú cambia según el frontend: `menu.header` («PYMEHackers») en el AppIndicator y `app.title` («PYMEHackers Control Center») en la extensión.

## Estructura del proyecto

Toda la documentación del producto vive en `doc/`. `app-debian/` contiene `frontend/`, `backend/`, `build/` y `tests/`; `app-macos/` y `app-windows/` reservan esa misma estructura. `README.md` en la raíz sólo enlaza a esta documentación. Las reglas y el seguimiento del trabajo conservan sus ubicaciones obligatorias.


Notas de las plataformas pendientes: [macOS](macos/CODE.es-AR.md), [Windows](windows/CODE.es-AR.md).
