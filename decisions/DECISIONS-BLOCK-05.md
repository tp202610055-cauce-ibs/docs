# Decisiones Técnicas — Bloque 5 (Auditing, Notifications, Outbox, Workers, Reports)

**Estado:** Aprobadas
**Fecha de aprobación:** 1 de julio de 2026
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, módulos `Auditing`, `Notifications`, `Outbox`, `Reports`, `Workers` (capas Domain, Application, Infrastructure, Api y tests)

Fuente de verdad del Bloque 5. Complementa —no reemplaza— a los bloques anteriores. Si una implementación necesita desviarse, se escribe un ADR nuevo. Las **actas de cambio** (sección final) documentan las divergencias entre el prompt de origen y el código real; el código y estas decisiones ganan.

---

## DEC-B5-01 — Estrategia de auditoría en 4 capas (Opción A acotada)

| Capa | Componente | Scope | Persistencia |
| --- | --- | --- | --- |
| 1 HTTP | `AuditingMiddleware` | LOGIN, LOGOUT, FAILED_LOGIN, EXPORT | `SaveChanges` en `IServiceScope` propio |
| 2 MediatR | `AuditingBehavior` + `IAuditableCommand` | **Solo tablas SIN trigger** (`GenerateInvitationCode`, `RequestPasswordReset`, `ConfirmPasswordReset`) | Corre **antes** de `next()`: `LogAsync` (AddAsync) → `next()`; el `SaveChanges` del handler persiste atómicamente |
| 3 Explícita | `IAuditLogger.LogAsync` | Approve/Reject (recs), Export (report), y tablas no-trigger con contexto | Llamada **movida antes** del `SaveChanges` del handler; una sola transacción |
| 4 PostgreSQL | Triggers `AFTER I/U/D` + `audit_trigger_fn()` | Las 8 tablas de DEC-B5-03 (fuente de verdad) | Transacción de la operación disparadora |

**Atomicidad:** las capas 2 y 3 no llaman `SaveChangesAsync` propio (lo hace el handler). La capa 1 sí, en scope propio. La capa 4 es autónoma. Ver **acta A8** para el detalle del cambio respecto del prompt original (behavior antes de `next()`, scope acotado).

**No-duplicación:** una tabla se audita por **un solo** mecanismo. Las 8 tablas triggerizadas se auditan solo por trigger; sus handlers no marcan `IAuditableCommand` ni llaman `LogAsync`. Las tablas sin trigger se auditan por behavior o explícito. Approve/Reject sobre `recommendations` producen una fila `update` (trigger) más una fila `approve`/`reject` (explícita): no son duplicados, capturan semánticas distintas.

## DEC-B5-02 — Consulta de `audit_logs` sin endpoint HTTP

`audit_logs` solo se consulta vía Adminer o script administrativo durante el piloto. No hay endpoint público ni protegido. No existe rol Administrator; exponer auditoría abriría superficie de exfiltración clínica.

## DEC-B5-03 — Tablas cubiertas por triggers PostgreSQL

Triggers `AFTER INSERT/UPDATE/DELETE` sobre: `recommendations`, `meals`, `symptoms`, `ibs_sss_assessments`, `patient_profiles`, `patient_allergies`, `nutritionist_patient`, `recommendation_feedback`.

Fuera del scope de triggers (auditadas por capa 1, 2 o 3, o no auditadas): `users`, `invitation_codes`, `password_reset_tokens`, `consent_records`, `model_versions`, `food_items`, `custom_foods`, `clinical_notes`, `notifications`, `outbox_messages`, `clinical_reports_metadata`.

## DEC-B5-04 — Patrón outbox transaccional

Tabla `outbox_messages` (`outbox_id`, `aggregate_id`, `aggregate_type`, `event_type`, `payload_json` jsonb, `occurred_at`, `processed_at`, `attempts` smallint CHECK 0..10, `last_error`). Índice parcial `(occurred_at) WHERE processed_at IS NULL` + `(aggregate_type, aggregate_id)`.

**Escritura:** `OutboxWriter` (`AddAsync` sin `SaveChanges`) inyectado en handlers; se enrolla en el `ChangeTracker` del `UnitOfWork` del handler → un solo `SaveChanges` persiste entidad de negocio + eventos, atómico.

**Consumo:** `OutboxDispatcherHostedService` cada 5s. Lee ids `processed_at IS NULL ORDER BY occurred_at LIMIT 50`. **Procesa cada mensaje en su propio `IServiceScope` + `SaveChanges`** (ajuste 3): deserializa el payload, resuelve el `Type` del evento, `mediator.Publish(evento)`. Éxito → `MarkAsProcessed`. Fallo → `attempts+1`, `last_error`, backoff `2^attempts s` (techo 3600). A `attempts=10` → `processed_at=now()` + log CRITICAL (envenenado).

## DEC-B5-05 — Módulo Notifications

Tabla `notifications`. `NotificationDispatcherHostedService` cada 10s consume `status='pending' AND scheduled_for<=now() AND retry_count<3 ORDER BY scheduled_for ASC, notification_id LIMIT 20` (el `ORDER BY scheduled_for` garantiza el orden URL-antes-de-password del reporte, ajuste 4). Proveedores: `email`→`SmtpEmailNotificationSender`, `push`→`FirebaseCloudMessagingSender`. Reintentos backoff 1min→5min→30min, `retry_count` máx 3; al superar → `status='failed'`.

**Exactly-once-effect (ajuste 2):** los `INotificationHandler` que crean `Notification` verifican existencia previa por `(user_id, related_entity_type, related_entity_id, type)` antes de agendar, con índice único filtrado de respaldo, para tolerar el re-procesamiento del outbox sin duplicar notificaciones.

## DEC-B5-06 — Worker de expiración de recomendaciones

`RecommendationExpirationHostedService`, cadencia 6h (`Recommendations:ExpirationWorker:IntervalHours`). `UPDATE recommendations SET status='expired', updated_at=now() WHERE status IN ('generated','pending_review','approved') AND expires_at < now();` con log estructurado del recuento.

## DEC-B5-07 — Recordatorio semanal por notificación push

No hay scheduler de generación. `WeeklyRecommendationReminderHostedService` corre semanalmente (default lunes 9 AM Lima) y crea `Notification` `Reminder` para cada paciente con onboarding completo y sin recomendación viva del período. **El cálculo del próximo tick usa `TimeZoneInfo.ConvertTimeToUtc(...)` con la zona `America/Lima`, nunca aritmética directa (ajuste 5).** Config `Notifications:WeeklyReminder:{DayOfWeek,HourLocal,TimeZone}`.

## DEC-B5-08 — Módulo Reports (PDF)

QuestPDF community (MIT), `LicenseType.Community` al arrancar. Flujo: nutricionista `POST /reports/patients/{id}` → verifica asignación → `PdfReportGenerator` compone (perfil, alergias, comidas, síntomas, IBS-SSS, recomendaciones aprobadas, feedback) → contraseña 12 chars → cifra el PDF → sube a MinIO `clinical-reports` (`patients/{id}/{start}_to_{end}/{report-id}.pdf`) → URL prefirmada 60 min → 2 `Notification` email **separadas** (URL, y contraseña +120s) → audita `ExportPdf` → persiste `clinical_reports_metadata`. El PDF no incluye `keycloak_id`, `email`, `ip_address` ni metadata técnica; iniciales del paciente, no nombre completo.

## DEC-B5-09 — Auditoría de catálogo FODMAP y `model_versions`

Fuera de alcance. Solo capa 3 (explícita) si el equipo activa una carga masiva o cambio de versión activa. Sin triggers.

## DEC-B5-10 — Refactor del `AuditLogger` y retro-ajuste de handlers

`AuditLogger`: (1) deja de llamar `SaveChangesAsync` (solo `AddAsync`); (2) usa `AuditLog.Record(...)`; (3) resuelve el actor a la PK local (acta A1); si no hay usuario → `actor_user_id=NULL`; (4) log `Warning` en fallo.

Retro-ajuste (reglas en DEC-B5-01):
- **Quitar `LogAsync`** (trigger cubre): `DeclarePatientAllergy`, `RemovePatientAllergy`, `CreatePatientProfile`, `UpdatePatientProfile`, `CompletePatientOnboarding`, `CreateIbsSssAssessment`.
- **`IAuditableCommand`** (behavior antes de `next()`): `GenerateInvitationCode`, `RequestPasswordReset`, `ConfirmPasswordReset`.
- **`LogAsync` explícito movido antes del `SaveChanges`**: `RegisterPatient`, `CreateNutritionist`, `CreateCustomFood`, `UpdateCustomFood`, `DeleteCustomFood`, `CreateClinicalNote`, `SyncBatch`.
- **Agregar `LogAsync` explícito** (antes del `SaveChanges`): `ApproveRecommendation` (Approve+context), `RejectRecommendation` (Reject+reason), `GenerateClinicalReport` (ExportPdf).
- **Eliminar**: `RegisterLoginEvent`, `RegisterLogoutEvent` (command+handler+tests) y los endpoints `/auth/sessions`. LOGIN/LOGOUT/FAILED_LOGIN pasan al middleware (acta A3).

## DEC-B5-11 — Detalle del `PdfReportGenerator`

Contraseña 12 chars del alfabeto `A-Z a-z 2-9` (excluye 0/O/1/l), `RandomNumberGenerator.GetString`. **No se persiste** en BD ni logs; solo se envía por email. `clinical_reports_metadata` guarda el hecho de la emisión, no el contenido ni el secreto ni el URL efímero. Bucket `clinical-reports` (creado por seeder idempotente).

## DEC-B5-12 — Retención del outbox procesado

`OutboxRetentionHostedService` cadencia 24h. `DELETE FROM outbox_messages WHERE processed_at IS NOT NULL AND processed_at < now() - interval '30 days';` Config `Outbox:Retention:DaysToKeep=30`. Log del recuento.

---

## Actas de cambio (divergencias prompt → código real)

| # | Prompt | Implementado |
|---|---|---|
| A1 | `ICurrentUserService.UserId` = PK local | Devuelve el `sub` de Keycloak; el interceptor, el middleware y el `AuditLogger` resuelven keycloak→PK local vía `IUserRepository.FindByKeycloakIdAsync` (con cache). `actor_user_id` guarda `users.user_id`. |
| A2 | `users.fcm_token` opcional | Se agrega la columna nullable en la migración. Falta el endpoint `PUT /users/me/fcm-token` (deuda técnica pre-piloto); sin él, el push real no es alcanzable, pero la maquinaria (sender + `FakeFcmSender`) queda completa. |
| A3 | No hay endpoint de login | Se crea `POST /api/v1/auth/login` (passthrough a Keycloak `grant_type=password` vía `KeycloakTokenClient` nuevo) y `POST /api/v1/auth/logout` (revoke); coincide con el flujo de login ya documentado en `CLAUDE.md`. Se eliminan `/auth/sessions`. |
| A4 | Enum con `Insert`/`Export`/`DeleteAccount`; triggers escriben `'insert'` | El enum real es `Create`/`ExportPdf` (sin `DeleteAccount`). Los triggers escriben `'create'/'update'/'delete'` para no romper `SnakeCaseEnumConverter`; el reporte/middleware usan `ExportPdf` (`'export_pdf'`). |
| A5 | — | La función `audit_trigger_fn` usa `digest(...)` de `pgcrypto`; la migración ejecuta `CREATE EXTENSION IF NOT EXISTS pgcrypto` antes. |
| A6 | — | El `AuditActorContextInterceptor` se registra manualmente en `AddDbContext` (`options.AddInterceptors(...)`). |
| A7 | `RegisterMealCommand`, `RegisterSymptomCommand`, `RegisterIbsSssAssessmentCommand`, `SyncOfflineBatchCommand` | Nombres reales: `CreateMealCommand`, `CreateSymptomCommand`, `CreateIbsSssAssessmentCommand`, `SyncBatchCommand`. |
| A8 | Behavior "enrolla en ChangeTracker sin SaveChanges"; delta 1 con trigger | El `AuditingBehavior` corre **antes** de `next()` (hash del payload → `LogAsync` AddAsync → `next()`; el handler persiste atómicamente); scope acotado a tablas sin trigger; los explícitos se mueven antes del `SaveChanges`. Causa: imposible coordinar behavior post-`next()` con el `SaveChanges` propio del handler y el trigger simultáneo. Decisión: Opción A por compliance, atomicidad y menor riesgo de refactor. CA-B5-05 se reformula: el behavior no aplica a tablas triggerizadas; una tabla no-trigger auditada por behavior genera exactamente 1 fila. |
| A9 | Eventos de Recommendations publicados por MediatR directamente | El Dominio no puede referenciar MediatR (regla "Domain no depende de nada"). Los eventos siguen siendo `IDomainEvent` puros; un wrapper genérico `DomainEventNotification<TEvent> : INotification` en Application hace de puente: el `OutboxDispatcher` deserializa el evento, lo envuelve y hace `mediator.Publish(wrapper)`. Los handlers son `INotificationHandler<DomainEventNotification<TEvent>>`. |
| A10 | Correos del reporte encolados como `Notification` | El `GenerateClinicalReportCommandHandler` envía los 2 correos (URL y contraseña) de forma **síncrona** vía `IEmailSender` tras el `SaveChanges`, no vía la entidad `Notification`. Motivo: la contraseña no se persiste (DEC-B5-11) y encolarla en `notifications.body` la almacenaría. La entidad `Notification` queda para las notificaciones de recomendaciones (push/email). |
| A11 | `new_values_hash` = hash del payload crudo (ajuste 1) | `IAuditableCommand` expone `object AuditPayload => this;` (miembro por defecto); el `AuditingBehavior` hashea `AuditPayload`, no el comando crudo. Los comandos con secretos (`ConfirmPasswordResetCommand`) redefinen `AuditPayload` devolviendo una proyección sin token ni contraseña, para **no** incluir credenciales (ni sus hashes) en `audit_logs`, coherente con "el sistema nunca almacena hashes de contraseñas". Las notas clínicas de Approve/Reject se registran como hash SHA-256 en `new_values_hash` (nunca en claro). |
| A12 | Lógica de despacho dentro de los `BackgroundService` | **Testabilidad determinista** (evitar timers en las pruebas). Se extrae la lógica de despacho a servicios scoped inyectables: `OutboxBatchProcessor.ProcessAsync(outboxId)` y `NotificationBatchProcessor.DispatchDueAsync(now, batchSize)`. Los workers quedan como schedulers finos (timer + scope) que delegan; las pruebas de integración invocan el processor directamente. Sin cambios en cadencias, backoff ni comportamiento observable en producción. |
| A13 | Backoff del outbox calculado pero **no respetado** | `OutboxMessage.NextRetryDelay()` se calculaba pero `ListPendingIdsAsync` solo filtraba `processed_at IS NULL`, así que un mensaje fallido re-entraba cada tick (~5 s) ignorando el backoff exponencial (martilleo de la cola). Fix: `OutboxMessage.NextAttemptAt` (fijado en `RecordFailedAttempt = now + NextRetryDelay()`), columna `next_attempt_at` (migración `AddOutboxNextAttemptAt`), y `ListPendingIdsAsync(now, batchSize)` filtra `next_attempt_at IS NULL OR <= now`. El `OutboxBatchProcessor` toma el instante de `TimeProvider` (mockeable con `FakeTimeProvider` en pruebas). Descubierto al escribir el test C4. |
| A14 | Middleware audita LOGIN/LOGOUT sólo tras `next()` | Un login que **lanza** (credenciales inválidas → `InvalidCredentialsException`) hacía que la excepción saliera del `AuditingMiddleware` antes del bloque de auditoría, **sin** registrar FAILED_LOGIN. Fix: envolver `next()` en `try/catch when (isLogin)`, auditar FAILED_LOGIN y re-lanzar; la auditoría de éxito/logout sigue en el camino normal. Descubierto al escribir el test C2. |
| A15 | `set_config` del actor vía `Database.ExecuteSqlRawAsync` | `ExecuteSqlRawAsync` abría y cerraba **su propia** conexión, por lo que la variable de sesión `cauce.actor_user_id` (nivel de sesión, no `is_local`) no persistía hasta el `INSERT` del `SaveChanges` y el trigger registraba `actor_user_id` **nulo**. Fix: el `AuditActorContextInterceptor` abre la conexión del contexto (`OpenConnectionAsync` si estaba cerrada) y ejecuta `set_config` sobre **esa misma** conexión con un `DbCommand` parametrizado; el `SaveChanges` reutiliza la conexión abierta y el trigger ve el actor correcto. Descubierto al correr los tests C1 (actor nulo). |

### Ajustes de revisión (vinculantes)
1. `entity_id=null` en el behavior; `IAuditableCommand.AuditAdditionalContext` aporta identificadores **ofuscados** del payload (email enmascarado, `code`), persistidos en `additional_context`.
2. Exactly-once-effect: los handlers de notificación verifican existencia previa por `(user_id, related_entity_type, related_entity_id, type)` + índice único filtrado.
3. `OutboxDispatcher` procesa cada mensaje en su propio `IServiceScope` + `SaveChanges`.
4. `NotificationDispatcher` ordena `scheduled_for ASC, notification_id` (garantiza URL antes de password).
5. `WeeklyReminder` calcula el próximo tick con `TimeZoneInfo.ConvertTimeToUtc` (zona `America/Lima`).
