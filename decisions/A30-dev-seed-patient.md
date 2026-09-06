# Acta A30 — Paciente de prueba sembrado en Development (dev-seed-patient)

**Estado:** Aprobada
**Fecha:** 2026-07-08
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, rama `chore/dev-seed-patient` (capa Infrastructure — seeders; capa Api — config de Development). No toca el contrato de API.

---

## Contexto

El backend quedó cerrado en `v0.6.1-api-contract-hardening`. Antes de arrancar el ciclo Mobile-1 (Flutter)
se necesita ejecutar el happy-path autenticado end-to-end contra un **paciente real**: login por Direct
Access Grants → `GET /patients/me` → `POST /meals` con `Idempotency-Key` → consulta de historial/IBS-SSS.

El único usuario demo previo (`nutricionista.demo@cauce.local`, `DevAdminSeeder`) no sirve para ese flujo:
tiene el **rol equivocado** (nutricionista) y una **contraseña temporal** (required action `UPDATE_PASSWORD`)
que bloquea el Direct Access Grant. Sin un paciente sembrado con datos verificados, Mobile-1 arranca a ciegas
y el checklist de humo queda incompleto.

## Decisión

Se agrega un **`DemoPatientSeeder`** (Infrastructure) que provisiona `paciente.demo@cauce.local` con:

- **Identidad Keycloak:** usuario del realm `cauce` con rol `patient`, correo **verificado**
  (`CreateUserAsync(requireEmailVerification: false)`) y **contraseña permanente**
  (`IKeycloakAdminClient.ResetPasswordAsync`, sin required actions) → habilita el Direct Access Grant.
- **Cuenta local:** `User.CreatePatient` + `VerifyEmail()` (Active) + `EnrollInActivePilot()` (`IsInActivePilot=true`).
- **Perfil clínico:** `PatientProfile` (nac. 1990-05-15, `Female`, 62.5 kg, 162 cm, `IbsD`), onboarding completo.
- **Consentimiento:** `ConsentRecord` vigente (hash SHA-256 real de un texto de demo).
- **Vínculo:** asignación al nutricionista demo si existe (el `DevAdminSeeder` corre antes).
- **Historial mínimo:** 5 comidas (2 desayunos, 2 almuerzos, 1 cena; una con alimento personalizado),
  3 síntomas (uno asociado a una comida en la ventana de 4 h), 1 IBS-SSS de línea base (total **220**,
  moderado), 1 nota clínica. Timestamps **relativos a `UtcNow`** para que el seed no envejezca.

### Solo Development + idempotente

La cadena `RunDevelopmentSeedAsync` se invoca únicamente bajo `app.Environment.IsDevelopment()`
(`Program.cs`); además el seeder tiene su propio gate `DemoPatient:Enabled`. Las pruebas de integración usan
`UseEnvironment("Testing")` y **no** ejecutan la cadena, por lo que `paciente.demo@cauce.local` **no** existe
en Testcontainers. En Production no hay sección `DemoPatient` → `Enabled=false`. Es **idempotente**: si el
paciente ya existe (por correo) el seeder hace no-op; el historial se persiste en un único `SaveChanges`
transaccional (sin estado parcial ante fallo).

## Por qué no un flujo de invitación real para desarrollo

Reproducir el flujo real (nutricionista genera código de invitación → paciente se registra con el código →
verifica el correo en Mailpit → elige contraseña) es **multi-paso, manual y no determinista**: exige tráfico
HTTP, lectura de un correo en Mailpit y un cambio de contraseña. Eso contradice el propósito de un seed
(estado reproducible al arranque, sin intervención). El seed **cortocircuita** ese flujo **solo en DEV**; el
flujo de invitación real sigue siendo la única vía en Production.

## Actor NULL en filas de auditoría seedeadas

Sembrar el perfil, comidas, síntomas, IBS-SSS y la asignación dispara los triggers de auditoría de esas
tablas. En un seeder **no hay usuario HTTP**, por lo que el `AuditActorContextInterceptor` deja la GUC
`cauce.actor_user_id` vacía y `audit_trigger_fn` la resuelve con `NULLIF(current_setting(...), '')::uuid` →
`actor_user_id = NULL` (la columna es nullable). Es **correcto y consciente**, no un descuido: un actor NULL
significa semánticamente "no fue una acción humana atribuible", que es exactamente el caso del seed. Es
compatible con la Ley N° 29733 y la RM 688-2020/MINSA porque (1) los datos sembrados son **DEV-only** y no
salen de la máquina de desarrollo, y (2) toda acción **real** del piloto se ejecuta por HTTP con actor
autenticado, donde el interceptor sí puebla la GUC.

## Divergencias dominio ↔ especificación (se ajustó el seed, no el dominio)

Fiel al principio "si algo exige modificar el dominio para acomodar el seed, se cambia el seed":

- **Síntomas:** el dominio modela `Intensity` (1–100), no un campo "Severity". Los niveles descritos se
  mapearon a intensidades representativas (dolor abdominal 60, distensión 35, flatulencia 30).
- **Nota clínica:** `ClinicalNote` es autoría **del paciente** y se asocia a exactamente una comida o un
  síntoma; no existe una "nota del nutricionista sobre el paciente". Se sembró como nota del paciente sobre un
  síntoma, con timestamp coherente (posterior al síntoma).
- **Fecha de consentimiento:** se usó un timestamp **relativo** (~40 días atrás) en lugar de una fecha
  absoluta, para que el seed no envejezca.

Ninguna factory de dominio rechaza fechas pasadas (solo futuras), por lo que los timestamps relativos pasan
todas las invariantes sin tocar el dominio.

## Archivos

- **Nuevos:** `Cauce.Infrastructure/Persistence/Seeders/DemoPatientSeeder.cs`,
  `Cauce.Infrastructure/Identity/DemoPatientOptions.cs`, `docs/dev/SEED-USERS.md`, este acta.
- **Modificados:** `Cauce.Infrastructure/Persistence/Seeders/SeedingExtensions.cs` (cadena),
  `Cauce.Infrastructure/DependencyInjection.cs` (registro + binding de opciones),
  `Cauce.Api/appsettings.Development.json` (sección `DemoPatient`), `CLAUDE.md` (usuarios DEV + convención).

## Deuda / notas

- La contraseña del paciente demo vive en `appsettings.Development.json` y en `docs/dev/SEED-USERS.md`; **no**
  se escribe en logs. Es un valor de desarrollo, no un secreto de producción.
- Si el catálogo de alimentos aún no está sembrado (`< 3` ítems activos), el seeder persiste identidad + perfil
  y omite el historial, dejándolo para el próximo arranque con catálogo completo.
