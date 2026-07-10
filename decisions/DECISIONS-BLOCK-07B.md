# Decisiones Técnicas — Bloque 7b (Cierre de features clínicas independientes pre-OE3)

**Estado:** Aprobadas
**Fecha de aprobación:** 6 de julio de 2026
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, rama `feature/pilot-compliance` (capas Domain, Application, Infrastructure, Api y tests)

Fuente de verdad del Bloque 7b. Complementa —no reemplaza— a los bloques anteriores. Cierra los nueve
huecos funcionales independientes que faltaban para alcanzar el 100 % de cobertura de RF del piloto antes
de la defensa OE3: panel de triaje (US18), evolución del paciente para el nutricionista (US21), autoreporte
del paciente (US24), sugerencias de alimentos (US09 CA03), advertencia de alérgenos (US10 CA03), perfil
agregado (US28), glosario clínico (US27), recordatorios IBS-SSS (US12 CA02) y gráfico de evolución en el PDF
(TS11/US22 CA01). Las **actas de cambio** documentan las divergencias entre el prompt de origen y el código
real; el código y estas decisiones ganan.

**Nota de renumeración:** el prompt de origen pedía documentar las actas como A24–A28. La acta **A24 ya fue
usada por el Bloque 7a** (conjunto de estados visibles del paciente). Para no colisionar, las actas de este
bloque se renumeran a **A25–A29**.

---

## DEC-B7B-01 — Panel de triaje del nutricionista (US18)

- `ListAssignedPatientTriageRowsAsync` (reemplaza a `ListAssignedPatientSummariesAsync`) amplía la consulta
  del listado con subconsultas correlacionadas: puntaje y severidad IBS-SSS más recientes, última actividad
  (máximo de comidas/síntomas/evaluaciones) y conteo de recomendaciones en `PendingReview` vencidas (>24 h).
- Enum nuevo `PriorityLevel` (`None|Low|Medium|High`) en `Domain/Patients/Enums/`, **calculado en la capa de
  aplicación** (`ListAssignedPatientsQueryHandler`), no en SQL: High si hay revisiones pendientes vencidas o
  severidad severa; Medium si severidad moderada o inactividad prolongada (>7 días); Low con datos; None sin
  línea base ni actividad. Orden: `PriorityLevel` DESC → puntaje DESC → asignación ASC.

## DEC-B7B-02 — Evolución del paciente para el nutricionista (US21)

- Query `GetPatientEvolutionForNutritionist` (Policy=Nutritionist): verifica la asignación activa
  (`ActiveAssignmentExistsAsync`) → **403** (`PatientAccessNotAuthorizedException`) si no está asignado.
  Reutiliza el patrón de `GetIbsSssEvolution` y el `IRecommendationSupportingDataReader` (Bloque 7a) para la
  frecuencia de registro de 14 días. Devuelve serie IBS-SSS, línea base, más reciente, variación porcentual,
  respuesta clínica significativa (`IsClinicallySignificantImprovement`) y frecuencia de registro.
- Endpoint `GET /api/v1/nutritionists/me/patients/{patientId}/evolution`.

## DEC-B7B-03 — Autoreporte clínico del paciente (US24)

- Comando `GenerateMyClinicalReport` (Policy=Patient) reutiliza `IPdfReportGenerator` (PDF cifrado + MinIO +
  URL prefirmada) sobre los últimos 90 días del paciente. Resuelve el nutricionista asignado; **si no hay
  ninguno, la sección del nutricionista se omite por completo del PDF** (acta A25 de ajuste): `nutritionistId`
  se volvió `Guid?` a lo largo del lector/generador y `ClinicalReportData.NutritionistName` es nullable; el
  documento QuestPDF renderiza esa línea de forma condicional.
- Dos correos separados y síncronos **al propio paciente** (URL y contraseña); la contraseña nunca se
  persiste. Auditoría `ExportPdf` con actor = paciente. No se persiste `ClinicalReportMetadata` en el
  autoservicio (la trazabilidad queda en `audit_logs`), evitando así un cambio de esquema.
- Endpoint `POST /api/v1/patients/me/report`.

## DEC-B7B-04 — Sugerencias de alimentos (US09 CA03)

- Query `GetFoodSuggestions` (Policy=Patient) + `IFoodSuggestionsReader` (Infra) que materializa y agrupa en
  memoria (patrón del lector de reportes). Tres listas: frecuentes de 30 días (top 10 por conteo), recientes
  de 24 horas (máx. 10, del más reciente al más antiguo) y sugerencias del catálogo (10, deterministas por
  paciente + semana ISO del año mediante una ventana desplazada). Solo alimentos del catálogo (no
  personalizados).
- Endpoint `GET /api/v1/foods/suggestions`.

## DEC-B7B-05 — Advertencia de alérgenos en comida personalizada (US10 CA03)

- Interfaz nueva `ICustomFoodAllergenChecker` (Application) implementada en Infra reutilizando el
  `AllergyHeuristicMatcher` **por cada alergia individual**, para asociar cada ingrediente coincidente con la
  alergia y su severidad. El comando `CreateCustomFood` recibe `ConfirmedAllergens`; si hay coincidencias sin
  confirmar → **409** (`UnconfirmedAllergensException`) con cuerpo `{ detected, allergens:[{ ingredientName,
  allergenName, severity }] }` (el middleware adjunta las extensiones). Si el paciente confirma, se crea y el
  acuse queda en la auditoría (`acknowledged_allergens`).

## DEC-B7B-06 — Perfil agregado "mi perfil" (US28)

- Query `GetMyProfileSummary` (Policy=Patient): identificación (correo enmascarado `r***@dominio`), perfil
  clínico, nutricionista asignado y evolución IBS-SSS resumida (línea base, más reciente, cambio acumulado,
  respuesta significativa). `PilotStartDate` con **precedencia explícita**: línea base IBS-SSS → creación del
  perfil (si el onboarding está completo) → creación de la cuenta. **`PatientCode` no existe en el modelo, se
  omite** (divergencia menor).
- Endpoint `GET /api/v1/patients/me/summary`.

## DEC-B7B-07 — Glosario clínico (US27)

- Entidad `GlossaryTerm` (término único, definición para paciente y para nutricionista, categoría
  `Nutritional|ClinicalIbs|System`), migración `AddGlossary` y seeder idempotente con ~30 términos. Endpoints
  `GET /api/v1/glossary` (orden alfabético) y `GET /api/v1/glossary/search?q=` (búsqueda), ambos autenticados;
  la definición devuelta depende del rol del solicitante (tomado del JWT). La respuesta incluye
  `contentStatus: "draft-pending-clinical-review"`.
- **Búsqueda insensible a tildes con `unaccent`:** se habilitó la extensión PostgreSQL `unaccent`
  (`modelBuilder.HasPostgresExtension("unaccent")` → `CREATE EXTENSION` en la migración) y el repositorio usa
  `EF.Functions.Unaccent(...) ILIKE ...`. **Verificado en runtime** contra `postgres:16-alpine` efímero
  (buscar "distension" sin tilde encuentra "Distensión abdominal"). No hubo que degradar a ILIKE simple.

## DEC-B7B-08 — Recordatorios de evaluaciones IBS-SSS (US12 CA02)

- Entidad `IbsSssAssessmentSchedule` en **tabla separada** `ibs_sss_schedules` (no columnas sobre
  `ibs_sss_assessments`, acta A28), migración `AddIbsSssSchedules`. `CreateIbsSssAssessmentCommandHandler`
  cierra la agenda abierta y crea la siguiente (vencimiento a +14 días) en la misma transacción.
- `IbsSssScheduleProcessor` (Infra, invocable directo desde las pruebas con reloj controlado) envía un
  recordatorio push a las **48 horas** de vencida (idempotente por `reminder_sent_at`) y marca como
  **perdida** a los **7 días**. Worker `IbsSssReminderWorker` (diario 09:00 Lima→UTC vía `TimeZoneInfo`,
  toggle `Workers:IbsSssReminder:Enabled`, deshabilitado en tests).

## DEC-B7B-09 — Gráfico de evolución IBS-SSS en el PDF (TS11/US22 CA01)

- **Opción B (gráfico real) elegida por el usuario**, condicionada a verificar la compatibilidad de SkiaSharp
  entre ScottPlot y QuestPDF con un build limpio. **Verificación (acta A29):** QuestPDF 2024.12 **no depende
  del NuGet de SkiaSharp** (empaqueta su propio Skia nativo), por lo que ScottPlot 5.0.56 (SkiaSharp 2.88.9,
  con `SkiaSharp.NativeAssets.Linux.NoDependencies`) **no colisiona**; el build fue limpio (0 warnings). No se
  activó el fallback a Opción A.
- `IbsSssChartRenderer` (Infra) produce un PNG de línea (puntaje 0–500 vs fecha) con una línea de meta clínica
  en línea base − 50 puntos; se embebe en `ClinicalReportDocument`, de modo que aparece en **ambos** reportes
  (paciente y nutricionista). Si el renderizado falla, el documento omite el gráfico.

---

## Migraciones nuevas (dos)

- `AddGlossary` — tabla `glossary_terms` + extensión `unaccent`.
- `AddIbsSssSchedules` — tabla `ibs_sss_schedules` (FK a `users`).

---

## Actas de cambio (divergencias prompt → código real)

| # | Prompt | Implementado |
|---|---|---|
| A25 | US18 priorización y US24 con sección de nutricionista siempre presente | (1) La priorización se **calcula en la capa de aplicación** a partir de subconsultas SQL, no en SQL; una vista materializada a escala queda como **deuda técnica** (el piloto es n=20–50). (2) En el autoreporte del paciente **sin nutricionista asignado, la sección se omite por completo** del PDF (no un placeholder de texto): `nutritionistId` se volvió nullable a lo largo del generador/lector/documento. |
| A26 | Catálogo formal alergia↔alimento para US10 | Se **reutiliza el `AllergyHeuristicMatcher`** (heurística conservadora, DEC-B4-14) evaluado por alergia individual para armar el detalle del 409. El catálogo formal `allergy_food_items` con el nutricionista del Kaelín queda como **deuda técnica** (heredada del Bloque 4). |
| A27 | Glosario validado clínicamente | El contenido de los ~30 términos es un **borrador** (`contentStatus: "draft-pending-clinical-review"`) pendiente de validación con el nutricionista del Complejo Hospitalario Guillermo Kaelín — **deuda técnica**. La extensión `unaccent` **sí se pudo usar** (verificada en runtime); no fue necesario degradar a ILIKE simple. |
| A28 | Columnas de agenda sobre `ibs_sss_assessments` | La agenda se modela en una **tabla separada** `ibs_sss_schedules`, porque es un concepto distinto de la evaluación completada (una evaluación es inmutable; la agenda tiene ciclo de vida propio: pendiente → completada/perdida, con recordatorio). |
| A29 | Equivalencia/compatibilidad SkiaSharp ScottPlot↔QuestPDF incierta | **No hay conflicto:** QuestPDF 2024.12 empaqueta su propio Skia nativo y no referencia el NuGet de SkiaSharp, así que la SkiaSharp 2.88.9 de ScottPlot es independiente. Build limpio; las native assets de Linux vienen incluidas (prod-safe). Opción B confirmada; el fallback a Opción A **no** se activó. |

### Deuda técnica identificada (pre-piloto)

- Vista materializada del panel de triaje a escala (hoy subconsultas correlacionadas; suficiente para n=20–50).
- Catálogo formal `allergy_food_items` (reemplazo del matcher heurístico, heredado del Bloque 4).
- Validación clínica del glosario (~30 términos en borrador) con el nutricionista del Kaelín.
- Endpoint `PUT /users/me/fcm-token` para push real en producción (heredado del Bloque 5).
- Semántica definitiva del modelo ONNX y del scoring (heredado del Bloque 7a).
