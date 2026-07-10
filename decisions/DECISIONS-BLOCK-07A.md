# Decisiones Técnicas — Bloque 7a (Batch Recommendation + Detalle 4 bloques + Notif espera + ONNX dummy)

**Estado:** Aprobadas
**Fecha de aprobación:** 6 de julio de 2026
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, rama `feature/pilot-compliance` (capas Domain, Application, Infrastructure, Api y tests)

Fuente de verdad del Bloque 7a. Complementa —no reemplaza— a los bloques anteriores. Cierra todo lo
relacionado con `Recommendation`: creación manual, modificación (modify), archivado, la notificación de
espera al paciente en revisión HITL, el detalle en cuatro bloques, y el wiring ONNX end-to-end con un
modelo dummy swap-ready. Un solo cambio de dominio y **una sola migración** porque casi todo toca la
entidad `Recommendation`. Las **actas de cambio** documentan las divergencias entre el prompt de origen y
el código real; el código y estas decisiones ganan.

---

## DEC-B7A-01 — Batch de Recommendation (US29 + US17 CA03 + US30 + US14 CA03)

- **Entidad `Recommendation`** ampliada: `Title`, `Description`, `Steps` (`IReadOnlyList<string>?` → JSONB
  vía value converter), `IsActive` (default true), `ArchivedAt`, `ArchiveReason`, `ValidUntil`, `Source`
  (`RecommendationSource`). `ModelVersionId` → **nullable** (null en manuales). Enums nuevos:
  `ArchiveReason` (TemporalExpiration, ManualSubstitution, ObjectiveMet, PlanChange), `RecommendationSource`
  (EngineGenerated, Manual). Ampliados: `RecommendationStatus` (+ModifiedApproved, +ManualApproved),
  `ExplanationSource` (+Manual).
- **Factorías/métodos de dominio:** `CreateManual` (Status=ManualApproved, ModelVersionId=null,
  ConfidenceScore=1.0, ExplanationSource=Manual, 0 ítems permitidos), `ModifyByNutritionist`
  (PendingReview → ModifiedApproved, reemplaza ítems/contenido), `Archive` (flag IsActive=false + motivo).
- **State machine:** `PendingReview → ModifiedApproved`; `ModifiedApproved`/`ManualApproved → Delivered,
  Expired`. **Archivado NO es estado** (flag `IsActive`) — acta A22.
- **US29** `POST /api/v1/recommendations/manual` (Policy=Nutritionist): verifica asignación (403), audita
  `Approve` + `{source: manual}`, publica `RecommendationManuallyCreatedEvent` → push al paciente.
- **US17 CA03** `POST /api/v1/recommendations/{id}/modify`: verifica asignación + PendingReview, audita
  `Approve` + `{operation: modified_approved}`, publica `RecommendationModifiedApprovedEvent` → push.
- **US30 CA01** `POST /api/v1/recommendations/{id}/archive`: verifica asignación + estado terminal
  aprobado, audita `Update` + `{archive_reason}`.
- **US30 CA02** `RecommendationArchivalWorker` (diario ~03:00 UTC): `ExecuteUpdate` sobre `ValidUntil < now`
  + `IsActive` + estado terminal aprobado → `IsActive=false`, `ArchiveReason=TemporalExpiration`.
- **US14 CA03 filtros:** el paciente solo ve recomendaciones **activas** en estados visibles (acta A24);
  `GET /recommendations/{id}` → 404 para el paciente si está archivada o en estado no visible. El
  nutricionista ve todas.

## DEC-B7A-02 — Notificación de espera (US14 CA02)

`NotificationType.Info` nuevo. En `GenerateRecommendationCommandHandler`, si la recomendación queda en
`PendingReview` (auto-aprobación deshabilitada en el piloto), se agenda una `Notification` inmediata
Info/Push al paciente ("Tu recomendación está en revisión"), idempotente por el identificador de la
recomendación (`ExistsForRelatedAsync`). El replay de generación (mismo `Idempotency-Key`) no la duplica.

## DEC-B7A-03 — Detalle en 4 bloques (US15 CA03 + US15 CA02)

`RecommendationDetailDto` ampliado (retrocompatible): **Bloque 1** = `AiExplanation` + `ExplanationSource`
(ya existían); **Bloque 2** = `ReviewedByNutritionistName` (JOIN a `users` vía `FindByIdAsync`); **Bloque 3**
= `Steps` (vacío si null); **Bloque 4** = `SupportingData` (nuevo `IRecommendationSupportingDataReader`:
conteo de síntomas y comidas de 14 días, top-3 alimentos FODMAP alto consumidos, `CorrelationWindowHours=4`,
ventana `from`/`to`).

## DEC-B7A-04 — ONNX end-to-end (dummy swap-ready, TS07)

- Paquete `Microsoft.ML.OnnxRuntime`. `OnnxRecommendationEngine` reescrito: carga el modelo de
  `Recommendations:OnnxModelPath` (default `infrastructure/models/dummy_v0.0.1.onnx`, resuelto buscando
  hacia arriba desde el directorio de ejecución); si falta → **fallback silencioso al motor de regla**
  inyectado. Con el modelo cargado: descriptor `(dummy-v0.0.1, sha256, "Onnx", IsDummy=true)`, extrae 5
  features del `PatientContextSnapshot` (edad, IMC, años desde dx, fumador, alcohol), infiere la
  probabilidad de "avoid" y la modula por el nivel FODMAP de cada alimento candidato.
- `ModelVersion.IsDummy` (columna nueva, batcheada en la migración del item 1). El seeder deriva la versión
  activa del `_engine.Descriptor`, de modo que con `EngineKind="Onnx"` la versión dummy queda activa
  automáticamente y cada recomendación generada es trazable a `dummy-v0.0.1`.
- Script `backend/tools/generate_dummy_onnx.py` (sklearn `LogisticRegression`, 5 features / 3 clases,
  `skl2onnx`) + README en `infrastructure/models/`. El modelo real de Mirian se instala por swap del
  binario, sin cambios de código — acta A23.

---

## Migración nueva (una sola)

`20260706025102_AddRecommendationManualModifyArchive` — columnas nuevas de `recommendations` (con defaults:
`is_active=true`, `source='engine_generated'` como backfill; `model_version_id` nullable; `steps` jsonb) y
`model_versions.is_dummy` (default false).

---

## Actas de cambio (divergencias prompt → código real)

| # | Prompt | Implementado |
|---|---|---|
| A22 | Archivado con posible estado `Archived` | Se modela como **flag** `IsActive=false + ArchivedAt + ArchiveReason`, no como estado del enum `RecommendationStatus`, para no explotar la máquina de estados ni multiplicar las transiciones. Los estados terminales aprobados (`Approved`, `ModifiedApproved`, `ManualApproved`) siguen siendo entregables; el archivado es ortogonal. |
| A23 | Modelo ONNX real / equivalencia PyTorch↔ONNX <0.001 | Se genera un modelo **dummy** (regresión logística de pesos aleatorios) para demostrar la infra ONNX end-to-end. El reemplazo por el modelo real de Mirian Contreras es un **swap del archivo binario**, no de código (el motor resuelve el path y cae a regla si falta). La equivalencia numérica PyTorch↔ONNX <0.001 **no es verificable** con el dummy (pesos aleatorios); queda como deuda técnica. La semántica de las 5 features y del post-procesamiento por alimento (hoy: tendencia del paciente × nivel FODMAP) también es deuda técnica a definir con Mirian. |
| A24 | Paciente ve solo `{Approved, ModifiedApproved, ManualApproved}` | Se **extiende** el conjunto visible del paciente a `{Approved, ModifiedApproved, ManualApproved, Delivered, FeedbackReceived}` (activas). Excluir `Delivered`/`FeedbackReceived` rompería el flujo existente en el que el paciente entrega (marca recibida) y luego consulta su recomendación y su feedback. El paciente **no** ve `Generated`/`PendingReview` (recibe la notificación de espera, DEC-B7A-02), ni `Rejected`/`Expired`, ni las archivadas. `GetById` responde 404 (no 403) para el paciente ante una recomendación no visible, para no revelar su existencia. Consecuencia: se ajustaron tests de integración previos que consultaban como paciente una recomendación en `PendingReview` (ahora se verifica su estado interno por la base de datos). |

### Divergencias menores de nombres/rutas verificadas contra el código

- Config del motor: `Recommendations:EngineKind` (no `Recommendations:Engine`).
- `Microsoft.ML.OnnxRuntime` no estaba referenciado; se agregó. El `OnnxRecommendationEngine` previo
  lanzaba en el constructor (placeholder); se reescribió.
- `NotificationType` no tenía `Info`; se agregó.
- Ruta del listado del paciente: `GET /api/v1/recommendations/me` (no `/recommendations`).

### Deuda técnica identificada (pre-piloto)

- Modelo ONNX real de Mirian (swap del binario) y equivalencia numérica PyTorch↔ONNX <0.001.
- Semántica definitiva de las 5 features de entrada del motor ONNX y del scoring por alimento.
- Reglas FODMAP/de correlación para los síntomas nuevos (heredado del Bloque 6).
- Aplazado al Prompt 7b: resto de features clínicas independientes + glosario + recordatorios IBS.
