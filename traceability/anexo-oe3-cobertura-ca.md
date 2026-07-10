# Anexo OE3 — Matriz de cobertura de Criterios de Aceptación (Backend Cauce)

**Propósito.** Evidencia de trazabilidad para la defensa del OE3: para cada una de las US/TS del pliego,
qué criterios de aceptación (CA) están cubiertos al 100 %, cuáles con un placeholder documentado, y cuáles
quedan como deuda técnica reconocida, con un porcentaje agregado de cobertura de **CA** (no de US).

**Fecha:** 6 de julio de 2026 · **Alcance:** backend (ASP.NET Core 9, Clean Architecture) sobre la rama
`feature/pilot-compliance`, Bloques 3–7b, **625 pruebas verdes** (335 Domain + 85 Application + 62
Infrastructure + 143 Integración).

## Metodología y perspectiva

La clasificación se hace **desde el backend puro y su capacidad de integración con un frontend futuro**
(app Flutter / portal React aún no construidos). Cada CA se ubica en una de cuatro categorías:

- **Full (100 %)** — el backend entrega el endpoint / la lógica / la persistencia / la auditoría que el CA
  exige, con respaldo de prueba, migración o acta. Incluye los CA de "sabor frontend" (gráficos, pantallas)
  **cuando el backend expone el contrato de datos adecuado** para que el frontend se vincule directamente.
- **Placeholder documentado** — el backend es funcional pero con una simplificación explícita registrada en
  un acta de decisión (matcher heurístico, modelo dummy, campo faltante, período fijo, etc.).
- **Deuda técnica** — brecha de backend reconocida: parte del CA no está implementada.
- **N/A (frontend)** — CA puramente de cliente sin ninguna responsabilidad de backend (cálculo en vivo en el
  dispositivo, escritura local en SQLite, ocultar un valor en pantalla, reintento de UI). **Se excluye del
  denominador** del porcentaje.

**Fuentes de verdad.** Código de los cuatro proyectos; las 625 pruebas; las migraciones EF Core; y los
documentos de decisiones `DECISIONS-BLOCK-3/-04/-05/-06/-07A/-07B.md`. La trazabilidad CA→prueba detallada
de los Bloques 4 y 7b vive en `docs/traceability/acceptance-criteria-matrix.md`; este anexo la agrega y la
extiende a las 41 US/TS.

> **Nota de conteo.** El listado del pliego suma 42 identificadores (TS01–TS12 + US01–US30); el enunciado
> del OE3 menciona "41". Se incluyen las 42 filas sin excluir ninguna; la diferencia es de numeración del
> pliego, no de cobertura.

---

## Tabla de cobertura por US/TS

| US/TS | (a) Full 100 % | (b) Placeholder documentado | (c) Deuda técnica |
|---|---|---|---|
| **TS01** Keycloak y roles | CA01, CA02 | — | — |
| **TS02** Alta de nutricionistas | CA01, CA02 | — | — |
| **TS03** Esquema PostgreSQL | CA01, CA02 | — | — |
| **TS04** Audit log inmutable | CA01, CA02 | — | — |
| **TS05** Persistencia offline SQLite | CA02 | — | — |
| **TS06** API ingesta/síntomas/sync/history | CA01, CA02 | — | — |
| **TS07** Pipeline ONNX | CA02 | CA01 | — |
| **TS08** LLM con guardrails | CA01, CA02 | — | — |
| **TS09** Máquina de estados | CA01, CA02 | — | — |
| **TS10** Notificaciones push/correo | CA01 | CA02 | — |
| **TS11** Reportes PDF server-side | CA01, CA02 | — | — |
| **TS12** Catálogo de alimentos | CA01, CA02 | — | — |
| **US01** Registro de paciente | CA01, CA02, CA03, CA04 | — | — |
| **US02** Activación de nutricionista | CA01, CA02 | — | — |
| **US03** Perfil clínico inicial | CA01, CA02, CA03, CA05 | — | — |
| **US04** Línea base IBS-SSS | CA01, CA02 | — | — |
| **US05** Login del paciente | CA01, CA02 | — | — |
| **US06** Login del nutricionista | CA01, CA02 | — | — |
| **US07** Recuperación de contraseña | CA01, CA02 | — | — |
| **US08** Cierre de sesión | CA01, CA02 | — | — |
| **US09** Registro de comidas | CA01, CA02, CA03 | — | — |
| **US10** Alimentos personalizados | CA02 | CA01, CA03 | — |
| **US11** Registro de síntomas | CA01, CA02 | — | — |
| **US12** Cuestionario IBS-SSS periódico | CA01, CA02, CA03 | — | — |
| **US13** Notas clínicas de contexto | CA01, CA02 | — | — |
| **US14** Recepción de recomendación | CA01, CA02, CA03, CA04 | — | — |
| **US15** Explicabilidad (XAI) | CA01, CA02, CA03 | — | — |
| **US16** Retroalimentación (feedback) | CA01, CA02 | — | — |
| **US17** Validación por nutricionista | CA01, CA02, CA03, CA04 | — | — |
| **US18** Panel de triaje | CA01, CA02 | — | — |
| **US19** Generación de código de invitación | CA01, CA02 | — | — |
| **US20** Vinculación por código | CA01, CA02 | — | — |
| **US21** Métricas de evolución (nutricionista) | CA01, CA02 | — | — |
| **US22** Reporte PDF del nutricionista | CA01, CA02 | — | — |
| **US23** Gráficos de evolución (paciente) | CA01, CA02 | — | — |
| **US24** Reporte PDF personal del paciente | CA02 | CA01 | — |
| **US25** Descarga de datos personales | CA01, CA02 | — | — |
| **US26** Eliminación de cuenta | CA01, CA02 | — | — |
| **US27** Glosario clínico | CA01 | — | CA02 |
| **US28** Perfil del paciente | CA02 | CA01 | — |
| **US29** Creación manual de recomendación | CA01, CA02 | — | — |
| **US30** Archivado de recomendación | CA01, CA02 | — | — |

**CA marcados N/A (frontend), excluidos del denominador (4):** `TS05 CA01` (escritura local en SQLite),
`US03 CA04` (cálculo del BMI en vivo mientras se escribe), `US12 CA04` (no exponer el puntaje antes de
enviar), `US18 CA03` (reintento de carga del panel ante error de conectividad).

---

## Detalle de las categorías (b) y (c)

### Placeholder documentado (6 CA)

| CA | Qué está cubierto | Simplificación / acta |
|---|---|---|
| TS07 CA01 | Exportación ONNX y carga en ONNX Runtime end-to-end; recomendación trazable al modelo. | Modelo **dummy** (pesos aleatorios); la equivalencia numérica PyTorch↔ONNX < 0.001 no es verificable con él. Reemplazo = swap del binario (acta **A23**). |
| TS10 CA02 | Reintentos con backoff exponencial 1/5/30 min y `MaxRetries=3`; cada intento registrado. | No hay Dead Letter Queue separada: el estado terminal `Failed` cumple ese rol (acta **A20**). |
| US10 CA01 | Creación del alimento personalizado con ingredientes del catálogo, marcado como no validado. | El backend **no calcula** el perfil nutricional estimado agregado desde los ingredientes (`CustomFood` no persiste macronutrientes). |
| US10 CA03 | Advertencia de alérgeno con 409 + confirmación explícita + auditoría (`acknowledged_allergens`). | La detección usa el **matcher heurístico** conservador, no un catálogo formal `allergy_food_items` (actas **DEC-B4-14 / A26**). |
| US24 CA01 | PDF cifrado con comidas, síntomas, IBS-SSS y recomendaciones; contraseña por correo aparte; descarga. | El período es **fijo (últimos 90 días)**; falta exponer la selección de rango de fechas que pide el CA. |
| US28 CA01 | Resumen agregado (perfil clínico, fecha de inicio, nutricionista, IBS-SSS base/último/cambio, respuesta significativa) vía `GET /patients/me/summary`. | Falta el campo **"código del paciente"** (no modelado, divergencia del Bloque 7b); las alergias se sirven por un endpoint separado (`GET /patients/allergies`). |

### Deuda técnica (1 CA)

| CA | Qué está cubierto | Brecha reconocida |
|---|---|---|
| US27 CA02 | La búsqueda del glosario responde vacío cuando el término no existe. | No implementa la **sugerencia de términos similares** ni el flujo de **"solicitar adición"** del nutricionista. |

### Otras deudas técnicas registradas (no bloquean ningún CA del piloto)

Documentadas para trazabilidad; no impiden el cumplimiento de ningún CA a la escala del piloto (n=20–50):
vista materializada del panel de triaje a escala (acta A25), retención de objetos MinIO a 7 días (acta A16),
enriquecimiento FODMAP granular de `food_items` con las columnas en 0 (DEC-B4-08), validación clínica del
texto de consentimiento (Bloque 6) y del contenido del glosario (borrador, acta A27), y verificación manual
del bloqueo por fuerza bruta de Keycloak (acta A21).

---

## Cómputo agregado de cobertura de CA

| Métrica | Valor |
|---|---|
| Total de CA del pliego (42 US/TS) | **99** |
| CA N/A (frontend puro, excluidos del denominador) | 4 |
| **CA con componente backend (denominador)** | **95** |
| CA Full (100 %) | 88 |
| CA Placeholder documentado | 6 |
| CA Deuda técnica | 1 |

**Porcentajes sobre los 95 CA con componente backend:**

- **Cobertura full (100 %): 88 / 95 = 92,6 %**
- **Cobertura con placeholder documentado: 6 / 95 = 6,3 %**
- Deuda técnica: 1 / 95 = 1,1 %
- **Cobertura funcional del backend (full + placeholder): 94 / 95 = 98,9 %**

> Interpretación para la defensa: el backend cubre de forma funcional el **98,9 %** de los CA que le
> corresponden; de ese total, el **92,6 %** está sin ninguna reserva y el **6,3 %** opera con una
> simplificación explícita y trazable (modelo dummy, matcher heurístico, período fijo, campo faltante,
> DLQ-como-estado). Solo **1 CA** (sugerencias/solicitud del glosario) queda como deuda funcional, y los 4
> CA restantes del pliego son de responsabilidad exclusiva del cliente móvil/portal.
