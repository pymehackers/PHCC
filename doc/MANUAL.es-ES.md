# PYMEHackers Control Center: manual de uso

Este MANUAL también está disponible en:\
[en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), es-ES

Este manual explica cómo instalar, usar y mantener PHCC, la aplicación de escritorio de PYMEHackers. La implementación disponible es Debian (paquete `phcc`), con un menú para Sistemas, Ciberseguridad y el catálogo de [PHCC-modules](https://github.com/pymehackers/PHCC-modules). Consulta la [referencia técnica](CODE.es-ES.md). macOS y Windows aún no están implementados.

## Índice

1. [Requisitos](#requisitos)
2. [Instalación](#instalación)
3. [Primer uso](#primer-uso)
4. [El menú](#el-menú)
5. [Catálogo de módulos](#catálogo-de-módulos)
6. [Idiomas](#idiomas)
7. [Registros](#registros)
8. [Uso desde la línea de comandos](#uso-desde-la-línea-de-comandos)
9. [Actualizar, reinstalar y desinstalar](#actualizar-reinstalar-y-desinstalar)
10. [Solución de problemas](#solución-de-problemas)

## Requisitos

- Debian (o una derivada con `apt-get` y `dpkg`) en amd64 o arm64. El core se desarrolla sobre Debian 13 (trixie).
- Un escritorio gráfico:
  - **GNOME Shell 45 a 50**: el icono lo pone la extensión nativa `phcc@pymehackers.com`. Las versiones anteriores de GNOME (por ejemplo el GNOME 43 de Debian 12) no pueden cargarla.
  - **MATE, XFCE, Cinnamon, KDE Plasma, Unity y otros escritorios con bandeja del sistema**: el icono lo pone el programa `phcc` (AppIndicator). El panel debe tener un área de notificación o un applet de indicadores de estado.
- Un agente de autenticación de polkit en marcha en la sesión (GNOME, KDE y Cinnamon traen uno; en MATE y XFCE suele ser `mate-polkit` o `polkit-gnome`). Sin él, las operaciones del catálogo no pueden pedir la contraseña.
- Acceso a Internet hacia `github.com`, `api.github.com`, `raw.githubusercontent.com` y `codeload.github.com`.
- Acceso como root para la instalación (`su -` o una consola de root; no hace falta `sudo`).

## Instalación

### Instalador de una línea

Ejecuta como root:

```bash
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash
```

Si no tienes `curl`, instálalo antes con `apt-get install -y curl`.

El instalador:

1. Descarga el código de la rama `main` de [PHCC](https://github.com/pymehackers/PHCC) y compara su versión con la instalada.
2. Sólo cuando hay algo que compilar, actualiza los índices de apt e instala las herramientas de compilación (`build-essential`, `pkg-config`, `libgtk-3-dev`, `libayatana-appindicator3-dev`, `dpkg-dev`, `file`, `curl`, `ca-certificates`).
3. Compila el paquete `phcc` para la arquitectura del equipo, comprueba su contenido y lo instala con `apt-get`, que instala también las dependencias de ejecución (`curl`, `jq`, `pkexec`, las bibliotecas de GTK y de AppIndicator y, como recomendación, `libnotify-bin` para las notificaciones).
4. Anota todo lo que hace en `/root/phcc-install.log` (modo 600).

Puedes volver a ejecutarlo sin miedo: si la versión instalada ya es la del repositorio, lo indica y se detiene sin instalar nada.

### Compilar desde el código fuente

En un equipo Debian con el árbol de código (por ejemplo, un clon del repositorio):

```bash
app-debian/build/native/build.sh --install-deps
```

El paquete verificado queda en `app-debian/build/native/dist/phcc_<versión>_<arq>.deb`. Instálalo como root:

```bash
apt-get install -y ./app-debian/build/native/dist/phcc_0.0.2_amd64.deb
```

Opciones de `native/build.sh`: `--clean` borra antes los resultados de compilaciones anteriores, `--install-deps` instala antes las dependencias de compilación (como root, o mediante `sudo` si lo ejecuta otro usuario) y `--help` muestra la ayuda.

Para generar el paquete arm64 en un equipo amd64, usa el flujo de compilación cruzada:

```bash
app-debian/build/arm64-cross/build.sh --install-deps
```

Activa la arquitectura arm64 en dpkg (multiarch), instala el compilador cruzado y las bibliotecas arm64 y deja `app-debian/build/arm64-cross/dist/phcc_<versión>_arm64.deb`. Si `apt-get update` falla porque una fuente de terceros no ofrece arm64, añade `Architectures: amd64` a esa fuente en `/etc/apt/sources.list.d/` y vuelve a intentarlo.

Si el árbol de código está en un sistema de archivos de red o FUSE (sshfs), compila desde una copia en un disco local. Usa `--clean` siempre que el mismo árbol se haya compilado antes en otra arquitectura, para no empaquetar nunca un binario antiguo.

## Primer uso

- **GNOME Shell**: tras la primera instalación, cierra la sesión y vuelve a entrar para que el Shell registre la extensión nueva. En cada inicio de sesión, la entrada de autoarranque «PYMEHackers Control Center (activar el icono en GNOME)» activa la extensión automáticamente.
- **Otros escritorios**: el programa `phcc` arranca en cada inicio de sesión (en MATE, con un retardo de 3 segundos). Tras la primera instalación puedes arrancarlo al momento desde el menú de aplicaciones.
- **Cualquier escritorio**: la entrada «PYMEHackers Control Center» del menú de aplicaciones muestra el icono. Abrirla de nuevo nunca duplica el icono; te avisa con «El icono ya está en la barra superior.» o «El indicador ya está en ejecución.». En GNOME, si el Shell todavía no conoce la extensión, dice «Cierra la sesión y vuelve a entrar para terminar de activar el icono.».

## El menú

Haz clic en el icono de PYMEHackers Control Center de la barra superior. El menú contiene:

| Elemento | Qué hace |
|---|---|
| «PYMEHackers» (AppIndicator) o «PYMEHackers Control Center» (GNOME) | Título, no se puede pulsar |
| «Sistemas» | Módulos de Sistemas instalados; cada módulo abre un submenú con sus acciones |
| «Ciberseguridad» | Módulos de Ciberseguridad instalados, con sus acciones |
| «Catálogo de módulos» | Módulos publicados en PHCC-modules (consulta [Catálogo de módulos](#catálogo-de-módulos)) |
| «Salir» | Oculta el icono |

Una sección sin módulos muestra «(sin módulos instalados)». Los nombres de los módulos y de sus acciones (por ejemplo «Configurar» o «Ver detecciones») los aporta cada módulo y se ejecutan con tu usuario; las acciones que necesitan root piden ellas mismas la contraseña.

«Salir» sólo oculta el icono; los servicios de los módulos siguen funcionando. Con el AppIndicator termina el programa `phcc`; en GNOME desactiva la extensión. En los dos casos el icono vuelve en el siguiente inicio de sesión o al abrir «PYMEHackers Control Center» desde el menú de aplicaciones.

## Catálogo de módulos

«Catálogo de módulos» muestra los módulos publicados en [PHCC-modules](https://github.com/pymehackers/PHCC-modules): primero los de Sistemas y después los de Ciberseguridad, cada grupo ordenado por nombre.

| Lo que ves | Significado |
|---|---|
| «Cargando el catálogo…» | Se está descargando la lista |
| «No se pudo cargar el catálogo» | No hay conexión con GitHub, o hubo otro error (consulta [Solución de problemas](#solución-de-problemas)) |
| «(no hay módulos disponibles)» | El repositorio no tiene ningún módulo válido |
| «Hay una operación en curso…» | Se está instalando o quitando un módulo; las acciones quedan desactivadas hasta que termine |
| «Ejemplo 1.2.0» | Módulo no instalado, con la versión disponible |
| «Ejemplo 1.1.0 (instalado)» | Módulo instalado, con la versión instalada |
| «Ejemplo (no disponible para esta plataforma)» | El módulo no admite la arquitectura de este Debian; no se puede seleccionar |

Abre un módulo para ver su descripción y sus acciones:

- «Instalar» en los módulos que no están instalados.
- «Actualizar a 1.2.0» cuando la versión instalada es distinta de la publicada.
- «Reinstalar» y «Desinstalar» en los módulos instalados.

Al elegir una acción, polkit pide la contraseña de un administrador (en Debian, la de root, o la tuya si tu usuario pertenece al grupo `sudo`). Mientras la sesión siga activa, polkit recuerda la autorización durante unos minutos. Una notificación anuncia el inicio («Instalando Ejemplo…», «Actualizando Ejemplo…», «Reinstalando Ejemplo…», «Desinstalando Ejemplo…») y otra el resultado:

- «Ejemplo: operación completada.»
- «Ejemplo: la operación falló. Tienes los detalles en /var/log/phcc-modules.log.»
- «Ejemplo: autorización cancelada.» (se cerró el diálogo de la contraseña)
- «Ejemplo: autorización denegada o no hay ningún agente de autenticación disponible.» (la contraseña no era correcta o no hay ningún agente de polkit en la sesión)

Cuando la operación termina, se recargan el catálogo y las secciones, así que un módulo recién instalado aparece al momento en «Sistemas» o en «Ciberseguridad», y uno desinstalado desaparece.

El catálogo se guarda durante 10 minutos. «Actualizar el catálogo» lo descarga de nuevo al momento y además reconstruye las secciones (útil tras instalar un módulo desde una terminal). Cada instalación usa siempre un catálogo recién descargado.

## Idiomas

El core sigue el idioma de tu sesión (las variables `LANGUAGE`, `LC_ALL`, `LC_MESSAGES` y `LANG`, en ese orden):

| Locale de la sesión | Idioma del core |
|---|---|
| `en_GB` | en-GB |
| `en_US` y cualquier otro `en_*` | en-US |
| `es_AR` | es-AR |
| `es_ES` y cualquier otro `es_*` (`es_MX`, `es_CL`...) | es-ES |
| Cualquier otro | en-US |

Después de cambiar el idioma de la sesión, cierra la sesión y vuelve a entrar. Los nombres y las acciones de los módulos los aporta cada módulo y usan las traducciones que el módulo incluya. El diálogo de la contraseña usa las traducciones de la política de polkit.

## Registros

- **Operaciones sobre módulos**: `/var/log/phcc-modules.log` (lo puede leer root). Cada operación añade líneas con la fecha UTC en el formato del proyecto, seguidas de toda la salida del instalador del módulo:

  ```text
  2026-10-29@13-59-59.723 install example: started
  2026-10-29@14-00-41.118 install example: completed
  ```

  La primera línea significa que la operación empezó el 2026/10/29@13:59:59.723 (UTC). Léelo como root con `tail -n 50 /var/log/phcc-modules.log`.
- **Instalación del core**: `/root/phcc-install.log`.
- **Mensajes del indicador**: el registro de la sesión, por ejemplo `journalctl --user -b | grep PYMEHackers` o `~/.xsession-errors`, según el escritorio.
- **Mensajes de la extensión de GNOME**: `journalctl -b /usr/bin/gnome-shell | grep "PYMEHackers Control Center"`.

## Uso desde la línea de comandos

El helper del catálogo también se puede usar desde una terminal:

```bash
# Listar el catálogo (cualquier usuario); --refresh se salta la caché de 10 minutos
/usr/libexec/phcc/phcc-modules list --refresh

# Instalar, actualizar, reinstalar o desinstalar un módulo (como root)
/usr/libexec/phcc/phcc-modules install example
/usr/libexec/phcc/phcc-modules uninstall example

# Lo mismo desde un usuario normal, con el diálogo de contraseña de polkit
pkexec /usr/libexec/phcc/phcc-modules reinstall example
```

`list` imprime un módulo por línea con 7 campos separados por tabuladores: id, sección, versión disponible, versión instalada, admitido (`1`) o no (`0`), nombre y descripción. Los errores se muestran en la terminal, así que es la mejor forma de averiguar por qué aparece «No se pudo cargar el catálogo».

`phcc-show` muestra el icono desde una terminal igual que la entrada del menú de aplicaciones.

## Actualizar, reinstalar y desinstalar

Ejecuta como root:

```bash
# Actualizar (o instalar): no hace nada si la versión instalada ya es la publicada
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash

# Reinstalar la misma versión
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash -s -- --reinstall

# Desinstalar el core
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

`--uninstall` ejecuta `apt-get remove phcc`. Los módulos instalados y sus servicios se quedan como están, las herramientas de compilación que instaló el instalador siguen instaladas y se conserva `/var/log/phcc-modules.log`. Para borrar también el registro y las carpetas vacías de módulos, ejecuta `apt-get purge phcc`. Si además quieres quitar los módulos, desinstálalos desde «Catálogo de módulos» antes de quitar el core; después, cada módulo se puede seguir quitando con su propio instalador y el argumento `--uninstall` (consulta su documentación en PHCC-modules).

El instalador siempre instala la versión publicada en el repositorio, aunque sea más antigua que la instalada.

## Solución de problemas

| Problema | Qué hacer |
|---|---|
| No hay icono en GNOME | Abre «PYMEHackers Control Center» desde el menú de aplicaciones. Comprueba `gnome-extensions info phcc@pymehackers.com`; si el Shell no la conoce, cierra la sesión y vuelve a entrar. Comprueba que las extensiones de usuario no estén desactivadas: `gsettings get org.gnome.shell disable-user-extensions` debe mostrar `false`. GNOME anterior a la versión 45 no está admitido. |
| No hay icono en MATE, XFCE, KDE... | Comprueba si el programa está en marcha con `pgrep -u "$USER" -x phcc`; si no, arráncalo con `phcc` desde una terminal y lee sus mensajes. Asegúrate de que el panel tiene un área de notificación o un applet de indicadores de estado. |
| No hay icono en Budgie o en GNOME Flashback | Estas sesiones se declaran como GNOME pero no ejecutan GNOME Shell, así que no se aplican ni la extensión ni el autoarranque de `phcc`. Ejecuta `phcc` a mano o añádelo a las aplicaciones de inicio de la sesión. |
| «No se pudo cargar el catálogo» | Comprueba la conexión a Internet y la fecha y la hora del equipo (HTTPS falla con el reloj mal). Ejecuta `/usr/libexec/phcc/phcc-modules list --refresh` en una terminal para ver el error. La API de GitHub permite 60 peticiones por hora sin autenticar desde una misma IP pública; si muchos equipos la comparten, espera y usa «Actualizar el catálogo» más tarde. |
| «(no hay módulos disponibles)» | El repositorio todavía no tiene ningún módulo válido, o ninguno tiene un `module.json` correcto. |
| Un módulo aparece como «(no disponible para esta plataforma)» | El módulo no admite `debian-amd64` o `debian-arm64` (la de tu equipo). |
| No aparece ningún diálogo de contraseña y la notificación dice «autorización denegada o no hay ningún agente de autenticación disponible» | Arranca un agente de autenticación de polkit en tu sesión (consulta [Requisitos](#requisitos)). |
| «...la operación falló. Tienes los detalles en /var/log/phcc-modules.log.» | Lee el final del registro como root: la salida del instalador del módulo explica el error. |
| Un módulo está instalado pero no aparece en su sección | El módulo debe instalar su manifiesto en `/usr/share/pymehackers/modules/sys/` o en `/usr/share/pymehackers/modules/cs/`. Usa «Actualizar el catálogo», o sal del indicador y vuelve a arrancarlo. |
| Un módulo que se retiró del repositorio no se puede desinstalar desde el catálogo | Usa el instalador del propio módulo con `--uninstall`, o quita su paquete con `apt-get remove`. |
| No hay notificaciones en escritorios distintos de GNOME | Instala `libnotify-bin`. |
| El instalador de una línea falla | Lee `/root/phcc-install.log`. Debe ejecutarse como root, en Debian o una derivada, con acceso a GitHub. |

Notas de las plataformas pendientes: [macOS](macos/MANUAL.es-ES.md), [Windows](windows/MANUAL.es-ES.md).
