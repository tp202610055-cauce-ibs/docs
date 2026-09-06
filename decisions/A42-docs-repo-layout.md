# Acta A42: Normalización del layout del repo docs y política de ignorados

**Estado:** Aprobada
**Fecha:** 2026-09-06
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Estructura del repositorio `docs`. No toca código, contrato de API ni configuración de infraestructura.

---

## Contexto

El bloque de limpieza posterior a Backend-Cleanup-1 encontró el repo `docs` con diez elementos sin
commitear: las ocho actas A30 a A37, el product backlog, la matriz de trazabilidad del bloque de
identidad, un mockup móvil modificado y el directorio de mockups del portal web. Todo es evidencia
académica y debe estar versionado.

Al inventariar el árbol para commitearlo aparecieron dos problemas de estructura que conviene resolver
antes de que los archivos entren al historial, no después.

**Problema 1: espacio en la ruta del backlog.** El directorio se llamaba `product backlog/` y el archivo
`Product Backlog.csv`. Un espacio en la ruta obliga a comillas en cualquier comando, script o pipeline
que la toque, y es una fuente silenciosa de errores en herramientas que no citan correctamente.

**Problema 2: convención de nombres inconsistente.** Los directorios de primer nivel del repo mezclan dos
esquemas: `01-diagrams`, `02-design-system` y `03-mockups` llevan prefijo numérico, mientras `decisions`,
`traceability` y el backlog no.

**Problema 3: el repo no tenía `.gitignore`.** Ninguna regla de exclusión, en un repo donde el backlog se
exporta desde Excel y la tesis se escribe en `.docx`. Ambos formatos generan archivos de bloqueo
temporales (`~$nombre`) junto al original mientras están abiertos.

El momento es el correcto porque los tres afectan a archivos **untracked**: renombrar ahora es una
operación de sistema de archivos, sin `git mv` y sin historia que reescribir.

## Decisión

**1. El backlog pasa a `04-product-backlog/product-backlog.csv`.** Se elimina el espacio en el directorio y
en el archivo, y se adopta el prefijo numérico que ya usan los otros directorios de artefactos entregables.

| Antes | Después |
| --- | --- |
| `product backlog/Product Backlog.csv` | `04-product-backlog/product-backlog.csv` |

**2. El prefijo numérico aplica a los directorios de artefactos entregables**, que son los que el lector de
la tesis recorre en orden: `01-diagrams`, `02-design-system`, `03-mockups`, `04-product-backlog`.
`decisions/` y `traceability/` quedan **sin prefijo de forma deliberada**: son series vivas y transversales
que crecen a lo largo de todo el proyecto, no una etapa del recorrido. Renombrarlas además exigiría
`git mv` sobre directorios ya versionados, con costo en la historia y cero beneficio.

**3. Se agrega un `.gitignore` preventivo** en la raíz del repo, con tres bloques: artefactos de sistema
operativo, bloqueos temporales de Office y configuración local de IDE. Al momento de aprobarse esta acta
**ninguna regla ignora un archivo existente**: el escaneo del árbol no encontró un solo archivo a excluir.
La regla que motiva el resto es `~$*`, para que un export del backlog hecho con el Excel abierto no
arrastre el archivo de bloqueo a la evidencia.

**4. La numeración de actas `A-` es global al proyecto Cauce, no por repositorio.** Esta acta es la A42 y
no la A38, aunque A38 sea el siguiente número libre dentro de `docs/decisions/`. Los números **A38 a A41
están reservados** para las cuatro actas de deuda técnica del backend (A38 para `isInActivePilot`
hardcodeado, A39 a A41 para las que cierra el bloque Backend-Fix-2). Al aprobarse esta acta esas cuatro
todavía no están escritas en ningún repo; cuando existan, enlazarlas desde aquí.

## Consecuencias

- La única referencia a la ruta vieja en todo el proyecto, `traceability/MATRIZ-IDENTIDAD.md` línea 9,
  se actualiza a `docs/04-product-backlog/product-backlog.csv` en el mismo bloque.
- Cualquier documento futuro que cite el backlog usa la ruta nueva. La vieja no existe.
- El repo `docs` queda con árbol limpio: cero archivos untracked y cero modificados sin commitear.
- Antes de crear un acta nueva hay que verificar el último número usado **en los tres repos**
  (`docs`, `backend`, `mobile`), no solo en el propio. El numerador es el proyecto.

## Pendiente identificado: hueco P15 en los mockups del portal web

El inventario de `03-mockups/web/` dejó ver un salto en la numeración de pantallas:

| Archivo | Pantalla |
| --- | --- |
| `P13-dashboard.html` | Dashboard |
| `P14-pacientes.html` | Lista de pacientes |
| **(falta)** | **P15, sin definir** |
| `P16-cola-hitl.html` | Cola HITL |
| `P17-recomendacion-manual.html` | Recomendación manual |

El archivo no existe en el directorio. Por su posición en la secuencia, entre la lista de pacientes y la
cola HITL, lo esperable es que P15 sea el **detalle de un paciente**, que es la pantalla que consume
`GET /api/v1/nutritionists/me/patients/{id}` y `GET /api/v1/nutritionists/me/patients/{id}/evolution`
(US18 y US21), hoy sin mockup.

Queda registrado como **pendiente del bloque Web-Portal-1**: definir si P15 se diseña, o si la numeración
se cierra y se documenta el salto. Mientras tanto, un lector de la evidencia académica ve un hueco sin
explicación. Esta acta es esa explicación.

## Referencias

- `docs/.gitignore` (creado por esta acta).
- `docs/04-product-backlog/product-backlog.csv`.
- `docs/traceability/MATRIZ-IDENTIDAD.md`, línea 9 (referencia actualizada).
- `docs/03-mockups/web/`, cuatro mockups del portal del nutricionista.
- Actas [A30](A30-dev-seed-patient.md) a [A37](A37-keydb-connection-string-password.md), commiteadas en el mismo bloque.
