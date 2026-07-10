# Decisiones Técnicas — Bloque 6 (Cierre P0 Ley 29733 + Notificaciones nutricionista + Trivialidades)

**Estado:** Aprobadas
**Fecha de aprobación:** 5 de julio de 2026
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, rama `feature/pilot-compliance` (capas Domain, Application, Infrastructure, Api y tests)

Fuente de verdad del Bloque 6. Complementa —no reemplaza— a los bloques anteriores. Cierra las brechas P0 de compliance de la Ley N° 29733, las notificaciones al nutricionista y las trivialidades pendientes antes de la exposición del OE3. Reutiliza los patrones del Bloque 5 (Clean Architecture + CQRS + DDD + outbox + notifications + reports + workers) sin introducir patrones nuevos. Las **actas de cambio** (sección final) documentan las divergencias entre el prompt de origen y el código real; el código y estas decisiones ganan.

---

## DEC-B6-01 — Exportación / portabilidad de datos del paciente (US25)

`ExportMyDataCommand` (Policy=Patient) → `IClinicalDataExporter` (Application) implementado en `Cauce.Infrastructure/Patients/ClinicalDataExporter.cs`. La construcción del archivo se separa en una función **pura** `ClinicalDataArchiveBuilder.Build(ClinicalDataSet)` (sin E/S), testeable sin infraestructura. Nueve CSV por entidad (comidas, síntomas, IBS-SSS, recomendaciones, feedback, perfil, alergias, `consent_records`, `audit_logs` donde el paciente es actor), empaquetados en ZIP con `System.IO.Compression.ZipArchive`, subidos a MinIO (bucket `patient-exports`) y devueltos como URL prefirmada (validez 7 días, máximo S3/MinIO). **CA02:** encabezados CSV siempre presentes aunque no haya filas. Auditoría explícita `AuditActionType.Export` sobre entidad `"PatientData"` con `additional_context = { counts: {...} }`. Endpoint: `GET /api/v1/patients/me/export-data`.

## DEC-B6-02 — Eliminación de cuenta / derecho al olvido (US26)

`DeleteMyAccountCommand(bool confirmedActivePilotAcknowledged)` (Policy=Patient). **Anonimización, no borrado físico:** `User.Anonymize(int patientRoleId)` (email → `deleted-{userId}@anonymized.local`, nombre → `"Usuario anonimizado"`, token FCM → null, `Status → Inactive`; lanza `OnlyPatientsCanBeAnonymizedException` si no es paciente) + `IKeycloakAdminClient.DisableUserAsync` (disable, no delete — acta A17) + correo de confirmación al email original (capturado antes de anonimizar). `consent_records` queda intacto (trigger de inmutabilidad). Auditoría explícita `AuditActionType.Delete` sobre `"User"` con `{ operation: "anonymization", keycloak_action: "disable" }`. **Gate de piloto activo (CA02):** campo `User.IsInActivePilot` (default false); si `true` y `confirmed=false` → 409 `ActivePilotRetentionException` (acta A16). Endpoint: `DELETE /api/v1/patients/me?confirmedActivePilotAcknowledged={bool}`. Migración `AddUserIsInActivePilot`.

## DEC-B6-03 — PDF del consentimiento aceptado (US01 CA04)

`GetMyConsentPdfQuery` (Policy=Patient) → `IConsentPdfRenderer` (Application) implementado con QuestPDF (`ConsentDocument` + `QuestPdfConsentRenderer`). Texto desde `ConsentDocumentOptions.Text` (config `Consent:Text`, ya existente en `appsettings.json` con placeholder — no requirió config nueva). Banner inicial "Documento en revisión clínica (borrador)". Encabezado con nombre, email, versión, timestamp de aceptación y hash SHA-256. **Sin cifrado** (dato propio del paciente); binario `application/pdf`, sin MinIO. Endpoint: `GET /api/v1/patients/me/consent/pdf`. `ConsentRecordNotFoundException` → 404 si no hay consentimiento vigente.

## DEC-B6-04 — Bitácora separada de intentos de modificar `audit_logs` (TS04 CA02)

Migración `AddAuditTamperWarning`: `CREATE OR REPLACE FUNCTION reject_audit_log_modification()` añade un `RAISE WARNING 'audit_tamper_attempt actor=% operation=% at=%'` (con GUC `cauce.actor_user_id`, `TG_OP`, timestamp UTC) **antes** del `RAISE EXCEPTION`; el WARNING escribe al server log fuera de la transacción abortada, por lo que sí persiste. El `ExceptionHandlingMiddleware` detecta la `Npgsql.PostgresException` de violación (`SqlState = 23514` + mensaje con `audit_logs`), responde 403 y registra un `SecurityEvent` de nivel Error con propiedades estructuradas `event_type=audit_tamper_attempt`, actor, ip, table (acta A18).

## DEC-B6-05 — Catálogo de 9 síntomas (US11 CA01)

`SymptomType` amplía a `Nausea = 6`, `Reflux = 7`, `Urgency = 8` (sin renumerar los existentes 0–5). `SnakeCaseEnumConverter` los serializa `nausea`/`reflux`/`urgency`. El validador `CreateSymptomCommandValidator` usa `IsInEnum()`, que los acepta sin cambios; sin migración (no hay CHECK sobre `symptom_type`). El `FodmapRuleRecommendationEngine` no tiene reglas para los nuevos síntomas (acta A19).

## DEC-B6-06 — Nota de aprobación ≥ 20 caracteres (US17 CA01)

`ApproveRecommendationCommandValidator`: `MinimumLength(10)` → `MinimumLength(20)` con mensaje `"La nota clínica de aprobación debe tener al menos 20 caracteres."`. El pipeline de validación (FluentValidation) se traduce a **400** `application/problem+json` (no 422 — así lo mapea `ExceptionHandlingMiddleware` en todo el codebase). `Modify` no se implementa (Prompt 7).

## DEC-B6-07 — Recordatorio de feedback 24h post-entrega (US16 CA01)

`DeliverRecommendationCommandHandler` agenda, tras la transición a `Delivered` y en la misma transacción, una `Notification.Schedule(patientId, Reminder, Push, "¿Cómo te fue con la recomendación?", ..., deliveredAt + 24h, "recommendation", recommendationId)` vía `INotificationScheduler`. El `NotificationDispatcherWorker` la envía cuando vence. Cero infraestructura nueva.

## DEC-B6-08 — Notificaciones a nutricionista (US03 CA03, US04/US12 CA01, US20 CA01)

Tres eventos de dominio (`IDomainEvent` puros, forma espejo de `RecommendationGeneratedEvent`): `PatientSubtypeChangedEvent`, `IbsSssAssessmentSubmittedEvent`, `PatientLinkedToNutritionistEvent`. Publicados vía `IOutboxWriter.PublishAsync` antes del `SaveChanges` en `UpdatePatientProfileCommandHandler` (solo si el subtipo cambió — quita el TODO), `CreateIbsSssAssessmentCommandHandler` (siempre) y `RegisterPatientCommandHandler` (al vincular invitación). Auto-descubiertos por `OutboxEventTypeRegistry` (reflexión). Tres handlers `INotificationHandler<DomainEventNotification<TEvent>>` en `<Módulo>/EventHandlers/` (convención real del repo, no `Notifications/Handlers/`) resuelven el nutricionista (via `INutritionistPatientRepository.FindActiveByPatientAsync` para los dos primeros; el tercero trae el `NutritionistUserId`), agendan `Notification` (canal Email, tipo Alert) con idempotencia `ExistsForRelatedAsync`. Clave de la entidad relacionada: `AssessmentId`/`InvitationCodeId` (naturales) y el `Id` del propio evento para el cambio de subtipo (acta A21-B6).

## DEC-B6-09 — Auditar el fallback del LLM (TS08 CA02)

`AuditActionType.LlmFallback` nuevo. La metadata del fallback (`FallbackReason`, `FallbackErrorType`, `FallbackDurationMs`, medida con `Stopwatch`) se surfaca desde `ExplanationResult` del `OllamaExplanationOrchestrator`, y `GenerateRecommendationCommandHandler` audita `LlmFallback` sobre `"Recommendation"` con `{ reason, error_type, duration_ms }` **donde existen el `recommendationId` y el `UnitOfWork`** (la recomendación no existe todavía dentro del orquestador — acta A20-B6). Sin migración (enum → string).

## DEC-B6-10 — Endpoint FCM + manejo de token inválido (TS10 CA01)

`PUT /api/v1/users/me/fcm-token` (`UsersController`, `[Authorize]` cualquier rol) → `UpdateFcmTokenCommand` → `User.RegisterFcmToken(token)`. **Auditoría explícita** `AuditActionType.Update` sobre `"User"` con `{ operation: "fcm_token_updated" }` (la tabla `users` no tiene trigger; se audita explícito por coherencia con el patrón del bloque 5). `FirebaseCloudMessagingSender`: ante `FirebaseMessagingException` con `MessagingErrorCode.Unregistered`/`InvalidArgument` (predicado `IsInvalidTokenError`), desvincula el token (`RegisterFcmToken(null)` + `SaveChanges` en scope propio), loguea Warning y devuelve `NotificationSendResult(false, null, "fcm_token_invalid_cleared")`. Sin DLQ separada: el estado `Failed` (3 fallos) es el equivalente (acta A20).

## DEC-B6-11 — Brute-force lockout Keycloak (TS01 CA02)

`infrastructure/keycloak/import/realm.json` ya tenía la configuración completa (`bruteForceProtected: true`, `failureFactor: 5`, `waitIncrementSeconds: 60`, `quickLoginCheckMilliSeconds: 1000`, `minimumQuickLoginWaitSeconds: 60`, `maxDeltaTimeSeconds: 43200`, `permanentLockout: false`). Sin cambio de código; verificación + acta A21.

---

## Actas de cambio (divergencias prompt → código real)

| # | Prompt | Implementado |
|---|---|---|
| A16 | `IsInActivePilot` con mecanismo de activación | Campo `bool` en `User` (default false), en `users` no en `PatientProfile` (dato de estado de cuenta, no clínico). **No hay mecanismo automático** para ponerlo en `true`: el equipo clínico Kaelín lo activará a mano (DB directa o endpoint admin futuro) al inscribir pacientes. Consecuencia: hoy todos los pacientes tienen `false`, así que toda solicitud real de eliminación pasa por el flujo CA01 sin gate; la lógica de CA02 queda implementada estructuralmente y se testea vía seed con `IsInActivePilot=true` (`User.EnrollInActivePilot()`). **Retención de objetos MinIO:** el bucket `patient-exports` se asegura vía `MinioBucketSeeder`; MinIO admite lifecycle policies pero el seeder no las configura → la caducidad de los ZIP exportados a los 7 días queda como **deuda técnica** (hoy solo caduca la URL prefirmada, no el objeto). |
| A17 | Anonimización + acción en Keycloak | Se prefiere `DisableUserAsync` (`enabled: false`, PUT `/admin/.../users/{id}`) sobre `DeleteUserAsync` para **preservar la trazabilidad de auditoría** exigida por la Ley N° 29733: el `keycloak_id` sigue existiendo y las filas clínicas anonimizadas mantienen su FK. Un usuario deshabilitado no puede iniciar sesión. Orden: `Anonymize` (memoria) → `DisableUserAsync` (externo; si falla, no se persiste y la baja es reintentable) → `LogAsync` → `SaveChanges` → correo de confirmación (best-effort). |
| A18 | Tabla `security_events` para tamper de `audit_logs` | Se descarta crear tabla `security_events` con `dblink`/`pg_background` (fragilidad, conexión secundaria, más superficie). En su lugar: `RAISE WARNING` (server log de PostgreSQL, persiste fuera de la transacción abortada) **+** Serilog enriquecido en el `ExceptionHandlingMiddleware` (log de nivel Error con `event_type=audit_tamper_attempt`, actor, ip, table). El marcado del `SecurityEvent` es la propiedad estructurada `event_type`; no se añade sink separado para el piloto. |
| A19 | Los 9 síntomas y las reglas del motor | El `FodmapRuleRecommendationEngine` no tiene reglas específicas para `nausea`/`reflux`/`urgency`; los trata como "otro" o los ignora en la correlación. Reglas específicas y de correlación son **deuda técnica del piloto** (a coordinar con el nutricionista Kaelín). |
| A20 | DLQ separada de notificaciones | No se crea DLQ separada: el estado `Failed` de la `Notification` tras 3 fallos (backoff 1/5/30 min) es el equivalente funcional. **Adición sobre el prompt (ajuste Trigo):** el `UpdateFcmTokenCommandHandler` audita explícitamente con `AuditActionType.Update` + `{ operation: "fcm_token_updated" }`, en vez de "audit implícito por trigger" — la tabla `users` **no** tiene trigger, así que el prompt asumía un mecanismo inexistente; se audita explícito por coherencia con el bloque 5. |
| A21 | Config brute-force de Keycloak | `realm.json` ya contenía todos los valores requeridos (`bruteForceProtected`, `failureFactor:5` = `maxLoginFailures` en el modelo de Keycloak, `waitIncrementSeconds`, `quickLoginCheckMilliSeconds`, `minimumQuickLoginWaitSeconds`, `maxDeltaTimeSeconds:43200`). No hubo cambio de archivo; validación manual por Trigo tras el deploy. No hay tests automatizados de config de infra. |
| A20-B6 | Auditoría del fallback dentro del orquestador | `IAuditLogger.LogAsync` se llama en `GenerateRecommendationCommandHandler` (no dentro de `OllamaExplanationOrchestrator`): la `Recommendation` —y por tanto el `recommendationId` y el `UnitOfWork`— no existen dentro del orquestador (Infraestructura), que corre **antes** de crear la entidad. El orquestador surfacea la metadata del fallback (`reason`/`error_type`/`duration_ms`) en `ExplanationResult`; el handler audita con el `recommendationId` y persiste atómicamente. |
| A21-B6 | Carpeta de handlers `Notifications/Handlers/` | La convención real del repo es `Cauce.Application/<Módulo>/EventHandlers/` (ver `Recommendations/EventHandlers/`). Los tres handlers de notificación al nutricionista van en `Patients/EventHandlers/`, `ClinicalRegistry/EventHandlers/` e `Identity/EventHandlers/`. La idempotencia del cambio de subtipo (sin entidad natural única) usa el `Id` del propio evento de dominio como `related_entity_id` (estable al re-serializar/deserializar en el outbox), permitiendo múltiples cambios distintos sin colapsar en dedup. |

### Migraciones nuevas

1. `20260705182639_AddUserIsInActivePilot` — columna `is_in_active_pilot boolean not null default false` en `users` (DEC-B6-02).
2. `20260705212334_AddAuditTamperWarning` — `CREATE OR REPLACE FUNCTION reject_audit_log_modification()` con `RAISE WARNING` (DEC-B6-04).

(Items 5, 6, 7, 8, 9, 10, 11: sin migración.)

### Deuda técnica identificada (pre-piloto)

- **Contenido del consentimiento**: el texto de `Consent:Text` es placeholder; pendiente de validación clínica por el equipo Kaelín.
- **Reglas FODMAP y de correlación** para `nausea`/`reflux`/`urgency` (DEC-B6-05, acta A19).
- **Lifecycle de objetos MinIO** para caducar los ZIP de export a los 7 días (acta A16); hoy solo caduca la URL prefirmada.
- **Activación de `IsInActivePilot`**: manual por Kaelín; no hay endpoint admin (acta A16).
- **Aplazado al Prompt 7**: batch de Recommendation + detalle de 4 bloques + ONNX dummy; resto de features clínicas + glosario + recordatorios IBS.
