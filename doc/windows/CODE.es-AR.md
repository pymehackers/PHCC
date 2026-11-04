# PYMEHackers Control Center (core) para Windows: referencia técnica

Este CODE también está disponible en:\
[en-GB](CODE.en-GB.md), [en-US](CODE.md), es-AR, [es-ES](CODE.es-ES.md)

Estado técnico de `app-windows/`. La implementación de escritorio disponible y el contrato de módulos están documentados en [CODE](../CODE.es-AR.md).

## Índice

1. [Estado](#estado)
2. [Estructura de carpetas](#estructura-de-carpetas)
3. [Módulos en Windows](#módulos-en-windows)
4. [Qué haría falta para implementar el core](#qué-haría-falta-para-implementar-el-core)

## Estado

El core de PYMEHackers Control Center **no está implementado en Windows**. `app-windows/` existe sólo para mantener la estructura de carpetas obligatoria del proyecto, tal y como recoge `RulesForThisProjectOnly.md`. No contiene código, ni flujo de compilación, ni instalador, así que todavía no hay mapa de módulos, índice de símbolos, flujos, mapa de rutas ni archivos instalados que documentar.

## Estructura de carpetas

| Carpeta | Contenido |
|---|---|
| `frontend/` | Vacía |
| `backend/` | Vacía |
| `build/` | Vacía |
| `tests/` | Vacía (las reglas del proyecto prohíben escribir tests) |

## Módulos en Windows

Los módulos que admiten Windows se instalan de forma independiente desde [PHCC-modules](https://github.com/pymehackers/PHCC-modules): cada módulo documenta allí su propio instalador, su servicio y su interfaz, y funciona sin el core. PHCC admite hoy los identificadores de escritorio de `module.json` `debian-amd64` y `debian-arm64`, así que ningún catálogo muestra compatibilidad con Windows.

## Qué haría falta para implementar el core

Un core para Windows debe cumplir los mismos dos contratos que el core de Debian: el [contrato de descubrimiento de módulos](../CODE.es-AR.md#contrato-de-descubrimiento-de-módulos) y el [contrato del catálogo de módulos](../CODE.es-AR.md#contrato-del-catálogo-de-módulos).

1. **Menú.** Un ícono en el área de notificación (bandeja del sistema) cuyo menú tenga la misma estructura: cabecera, «Sistemas», «Ciberseguridad», «Catálogo de módulos» y «Salir». Todos los textos visibles en `lang/{en-GB,en-US,es-AR,es-ES}.json`, siguiendo el idioma del usuario, con en-US como idioma por defecto y de respaldo.
2. **Descubrimiento.** Un registro donde cada módulo instale un manifiesto en una carpeta por sección (`sys`, `cs`) con un nombre traducido, un orden y una lista de acciones (etiqueta y orden que ejecutar), leído al construir el menú. Ningún nombre de módulo en el código. Hay que definir la ubicación y el formato para Windows y agregarlos al contrato de los dos proyectos.
3. **Catálogo.** Un helper que liste las carpetas de la raíz de PHCC-modules con un `module.json` válido, imprima las mismas líneas de 7 campos que `phcc-modules list` y ejecute el instalador de cada módulo con privilegios elevados (UAC) sólo después de que el usuario lo confirme, sin argumentos, con `--reinstall` o con `--uninstall`. Hay que agregar al contrato de `module.json` del `RulesForThisProjectOnly.md` de PHCC y de PHCC-modules un identificador de plataforma nuevo (por ejemplo `windows`) y una ruta de instalador (por ejemplo `<id>/app-windows/build/...`).
4. **Mínimo privilegio.** Sólo instalar, actualizar, reinstalar y desinstalar se ejecutan con privilegios elevados, y el repositorio sigue fijo en el helper.
5. **Compilación e instalación.** Scripts de compilación en `app-windows/build/` que apliquen el blindaje «core sin módulos», y un instalador de una línea idempotente que acepte `--reinstall` y `--uninstall`.
6. **Registros** con fechas UTC en el formato del proyecto (`2026-10-29@13-59-59.723`).
7. **Documentación.** Este CODE, el MANUAL y la documentación general, actualizados en los cuatro idiomas.
