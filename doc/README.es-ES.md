# PYMEHackers Control Center

Este README también está disponible en:\
[en-GB](README.en-GB.md), [en-US](README.md), [es-AR](README.es-AR.md), es-ES

## Qué es

PHCC es una aplicación exclusivamente de escritorio. Actualmente está implementada para Debian; macOS y Windows están pendientes.

PYMEHackers Control Center (PHCC) reúne las herramientas de sistemas y de ciberseguridad de PYMEHackers, llamadas módulos, en un único menú con dos secciones: Sistemas y Ciberseguridad.

- En Debian añade un icono a la barra superior del escritorio (GNOME Shell, MATE, XFCE, Cinnamon, KDE…).

Este repositorio es el core y no trae ningún módulo. Su Catálogo de módulos muestra los módulos publicados en [PHCC-modules](https://github.com/pymehackers/PHCC-modules) y los instala, actualiza, reinstala o desinstala con un clic.

## Capturas de pantalla

![Menú de PYMEHackers Control Center](https://raw.githubusercontent.com/pymehackers/PHCC/main/doc/screenshot.png)

## Instalación

Ejecútalo como `root`.

**Debian** (amd64 o arm64, con escritorio gráfico):

```bash
curl -fsSL https://raw.githubusercontent.com/pymehackers/PHCC/main/app-debian/build/install-update-reinstall-debian.sh | bash
```

Después instala los módulos que quieras desde el menú **Catálogo de módulos**.

## Lee la documentación

Explora:

- [doc/MANUAL.es-ES.md](MANUAL.es-ES.md) para aprender a instalarlo y a usarlo.
- [doc/CODE.es-ES.md](CODE.es-ES.md) para entender cómo está construido (para desarrolladores y para modelos de IA).

## Patrocina este proyecto

- **[Contrátame](mailto:nipegun@gmail.com?subject=I%20want%20to%20hire%20you%21)** para añadir nuevas funcionalidades.
- **GitHub Sponsors.** También puedes apoyar el proyecto económicamente en GitHub: [github.com/sponsors/nipegun](https://github.com/sponsors/nipegun).
