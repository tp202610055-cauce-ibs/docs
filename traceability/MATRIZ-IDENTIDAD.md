# Matriz de Trazabilidad — Bloque de Identidad

**Fecha:** 13 de julio de 2026 · **Backend:** tag `v0.6.2-dev-seed` · **Mobile:** `develop`, Mobile-1a cerrado (solo foundations)

**Propósito.** Establecer el estado real, verificado contra el código, de los criterios de aceptación del
bloque de identidad, antes de arrancar Mobile-1b. Es artefacto de tesis: cada fila lleva evidencia en
`archivo:línea` o la marca `NO EXISTE`.

**Fuente del texto de los CA:** `docs/04-product-backlog/product-backlog.csv`. El texto se transcribe del
backlog, resumido a una o dos líneas sin alterar su intención.

**Decisión de arquitectura vigente.** El móvil autentica contra `POST /api/v1/auth/login` del backend. El
acta M5 del mobile (Authorization Code + PKCE directo contra Keycloak) queda anulada. Motivo: el
`AuditingMiddleware` detecta el login solo por la ruta `POST /auth/login`
(`backend/src/Cauce.Api/Middleware/AuditingMiddleware.cs:46`), y `LoginCommandHandler` es el único que
escribe `users.last_login_at` (`backend/src/Cauce.Application/Identity/UseCases/Login/LoginCommandHandler.cs:45`).
Con PKCE directo, `audit_logs` quedaría sin registro de accesos y se incumpliría la Ley N° 29733.

**Contrato técnico de referencia:** `backend/docs/api/CONTRACT-IDENTITY-v1.md`.

## Semántica de las columnas

| Valor | Significado |
|---|---|
| **VERDE** | El CA se cumple hoy, end to end, con el código que existe |
| **PARCIAL** | Una parte existe y funciona; falta la otra para cerrar el CA |
| **ROJO** | No existe la capacidad que el CA exige |

Las rutas de evidencia del backend son relativas a `backend/`. Las del mobile, a `mobile/`.

---

## Matriz

| ID | Texto del CA | Responsable | Estado real | Evidencia | Gap concreto |
|---|---|---|---|---|---|
| **US01-CA01** | Registro exitoso con datos válidos: crea la cuenta, almacena la aceptación del consentimiento con timestamp y versión, envía correo de verificación y redirige al perfil clínico inicial. | Compartido | **PARCIAL** | `src/Cauce.Application/Identity/UseCases/RegisterPatient/RegisterPatientCommandHandler.cs:56-136` · `src/Cauce.Infrastructure/Identity/ConsentService.cs:41-51` | El móvil no puede construir un `consentTextHash` válido: ningún endpoint publica el texto ni la versión del consentimiento. Falta ese endpoint (o acordar réplica byte exacta del texto en el cliente) y construir el formulario. |
| **US01-CA02** | Rechazo por datos inválidos o correo duplicado: muestra un mensaje de error específico por cada campo incorrecto y conserva los datos válidos ya ingresados. | Compartido | **PARCIAL** | `src/Cauce.Api/Middleware/ExceptionHandlingMiddleware.cs:271-288` · `src/Cauce.Application/Identity/UseCases/RegisterPatient/RegisterPatientCommandValidator.cs` | El backend entrega errores por campo en `errors`. Falta el formulario móvil. Atención: las claves de `errors` llegan en **PascalCase** y el 400 de binding de `[ApiController]` **no trae `errorCode`**; el cliente debe manejar las dos formas de 400. |
| **US01-CA03** | Bloqueo sin aceptación del consentimiento: no permite avanzar, indica que el consentimiento es obligatorio y no crea ningún registro parcial. | Mobile | **ROJO** | Respaldo backend: `RegisterPatientCommandValidator.cs:25-28` (`consentTextHash` obligatorio) · Mobile: **NO EXISTE** | Construir la pantalla de consentimiento con el botón "Crear cuenta" deshabilitado hasta la aceptación. El backend ya rechaza un registro sin hash de consentimiento. |
| **US01-CA04** | Persistencia inmutable del consentimiento: `consent_records` con versión, timestamp, hash SHA-256 e IP; triggers de BD impiden modificar o eliminar; el usuario descarga el PDF del documento aceptado. | Compartido | **PARCIAL** | `src/Cauce.Infrastructure/Persistence/Migrations/20260624212001_AddIdentityTables.cs:219,232` (`trg_consent_records_prevent_update` / `prevent_delete`) · `src/Cauce.Application/Identity/UseCases/GetMyConsentPdf/GetMyConsentPdfQueryHandler.cs:31-40` | El backend cumple: persistencia, inmutabilidad por trigger y `GET /patients/me/consent/pdf`. Falta la pantalla de privacidad en el móvil con la descarga del PDF. |
| **US05-CA01** | Autenticación exitosa: valida credenciales contra Keycloak, inicia sesión segura con expiración definida y redirige a la pantalla principal. | Compartido | **PARCIAL** | `src/Cauce.Api/Controllers/AuthController.cs:83-94` · `src/Cauce.Infrastructure/Identity/KeycloakTokenClient.cs:43-90` | El backend entrega los tokens. Falta la pantalla de login, el guardado en `flutter_secure_storage` y el routing al Home. |
| **US05-CA02** | Bloqueo por intentos fallidos: tras cinco fallos bloquea temporalmente, **muestra un mensaje que indica el bloqueo y el tiempo de espera**, y registra el evento en el audit log. | Compartido | **PARCIAL** | Bloqueo: `infrastructure/keycloak/import/realm.json` (`bruteForceProtected: true`, `failureFactor: 5`) · Audit: `AuditingMiddleware.cs:108` (`FAILED_LOGIN`) · Mensaje y tiempo de espera: **NO EXISTE** | El backend **no expone el bloqueo ni el tiempo de espera**. `AccountLockedException` está mapeada a 423 (`ExceptionHandlingMiddleware.cs:163-164`) pero **nunca se lanza**, y `KeycloakTokenClient.cs:61-65` colapsa el 401 de Keycloak en `invalid_credentials`. Falta que el backend distinga el lockout y devuelva 423 con el tiempo restante. |
| **US07-CA01** | Enlace de recuperación enviado: token único con expiración de 30 minutos, correo con el enlace, mensaje genérico que no revela si el correo existe, y registro en el audit log. | Compartido | **PARCIAL** | `AuthController.cs:119-135` · `src/Cauce.Domain/Identity/PasswordResetToken.cs:16` (30 min) · `RequestPasswordResetCommand.cs:19,25` (auditado) | El backend cumple los cuatro puntos. **El enlace del correo no resuelve:** `ClientUrlProvider.cs:28-29` arma `{AppBaseUrl}/auth/password-reset?token=...` y en Development `AppBaseUrl` es `http://localhost:5074` (el backend), que no expone esa ruta. Falta apuntar `AppBaseUrl` a un deep link `cauce://` y construir la pantalla. |
| **US07-CA02** | Enlace expirado o ya utilizado: invalida el token, informa que ya no es válido o fue usado, y ofrece solicitar uno nuevo. | Compartido | **PARCIAL** | `ExceptionHandlingMiddleware.cs:165-168` (`invalid_password_reset_token`, `expired_password_reset_token`) · `PasswordResetToken.cs:106` (uso único) | El backend devuelve los dos `errorCode`. Falta la pantalla móvil que los interprete y ofrezca reenviar, más el deep link del CA anterior. |
| **US08-CA01** | Cierre de sesión exitoso: invalida el token JWT en Keycloak, elimina los datos de sesión del dispositivo, redirige al login y bloquea la navegación hacia atrás. | Compartido | **PARCIAL** | `AuthController.cs:102-111` · `KeycloakTokenClient.cs:93-108` (`LogoutAsync` revoca el refresh token) | El backend revoca el **refresh token**. El **access token sigue siendo válido hasta su expiración** (hasta 15 min), porque el backend lo valida offline como JWT. Falta el borrado del secure storage, el redirect y el bloqueo de back en el móvil. |
| **US08-CA02** | Cierre automático por inactividad: al expirar el JWT sin renovarse, cierra la sesión, informa que terminó por inactividad y redirige al login sin perder datos sincronizados. | Compartido | **ROJO** | Endpoint de refresh: **NO EXISTE** en `AuthController.cs`. `KeycloakTokenClient` solo implementa `LoginAsync` (`grant_type=password`) y `LogoutAsync` | El CA presupone un mecanismo de renovación ("sin haberse renovado") que **no existe**. Falta decidir la estrategia de refresh (endpoint nuevo en el backend, o `grant_type=refresh_token` directo contra Keycloak) y luego implementar la detección de expiración en el cliente. |
| **TS01-CA01** | Autenticación funcional con roles diferenciados: cada usuario recibe un JWT con sus claims de rol, el backend valida el token en cada petición y las rutas protegidas rechazan con 403 un rol incorrecto. | Backend + Keycloak | **PARCIAL** | `src/Cauce.Api/Program.cs:62-89` (validación JWT, policies `Patient` / `Nutritionist`) · `Program.cs:244-280` (mapeo de `realm_access.roles`) · Roles del realm: `realm.json` (`patient`, `nutritionist`) | El código funciona, pero **`realm.json` no contiene el audience mapper ni el default scope `basic`**. Un entorno limpio (`docker compose down -v` + re-import) emite tokens sin `aud=cauce-backend` (401) y sin `sub` (403). Los fixes de las actas A35 y A36 viven solo en la consola de Keycloak, no en el repo. Falta persistirlos en `realm.json`. |
| **TS01-CA02** | Bloqueo por intentos fallidos y registro en audit log: Keycloak bloquea la cuenta tras cinco fallos, el sistema registra el evento en el audit log con timestamp e IP, y el usuario no puede autenticarse hasta que expire el bloqueo. | Backend + Keycloak | **VERDE** | `realm.json` (`bruteForceProtected: true`, `failureFactor: 5`, `waitIncrementSeconds: 60`, `maxFailureWaitSeconds: 900`, `permanentLockout: false`) · `AuditingMiddleware.cs:108,140-148` (`FAILED_LOGIN` con `ipAddress` y `OccurredAt`) | Ninguno, **condicionado** a que el login pase por `POST /auth/login`. Con PKCE directo contra Keycloak el audit log quedaría vacío. La decisión de usar el passthrough sostiene este CA. |
| **TS05-CA01** | Escritura local sin conexión: el registro se guarda en SQLite con un `client_guid` único generado en el cliente, timestamp local y estado `sync_pending`, y la interfaz confirma el guardado. | Mobile | **ROJO** | **NO EXISTE** (Mobile-1a solo dejó foundations; `drift` está declarado en `pubspec.yaml` pero no hay esquema ni DAOs) | Implementar el esquema `drift` con `client_guid` y `sync_status`, los DAOs y la confirmación visual. |
| **TS05-CA02** | Idempotencia en la sincronización: el backend verifica el `client_guid`, no crea duplicados, confirma el registro existente, y el cliente pasa a `sync_completed`. | Compartido | **PARCIAL** | Backend: `POST /api/v1/sync/batch` existe y deduplica por `client_guid` (contrato `openapi-v1.0.0.json`) · Mobile: **NO EXISTE** | El backend ya garantiza la idempotencia. Falta el worker de sincronización del móvil y la transición de estado local. |
| **US20-CA02** | Registro sin código de invitación: permite completar el registro, marca al paciente como no asignado, le informa que no tiene nutricionista y **que puede ingresar el código más adelante desde la configuración de su perfil**. | Compartido | **PARCIAL** | Código opcional: `RegisterPatientCommand.cs:24` (`string? InvitationCode`) · `RegisterPatientCommandValidator.cs:33-36` · Canje posterior: **NO EXISTE** | El registro sin código ya funciona y el paciente queda sin nutricionista asignado. **No existe ningún endpoint para canjear un código después del registro**: el código solo se acepta en `auth/register` (`AuthController.cs:70`). Falta ese endpoint y la pantalla de perfil. |

**Recuento:** 15 filas. El prompt de origen enunció "14 criterios" pero su tabla enumera 15 (US01 aporta 4,
US05 2, US07 2, US08 2, TS01 2, TS05 2, US20 1). Se documentan los 15 enumerados.

---

## Resumen por estado

| Estado | Cantidad | CAs |
|---|---|---|
| VERDE | 1 | TS01-CA02 |
| PARCIAL | 11 | US01-CA01, US01-CA02, US01-CA04, US05-CA01, US05-CA02, US07-CA01, US07-CA02, US08-CA01, TS01-CA01, TS05-CA02, US20-CA02 |
| ROJO | 3 | US01-CA03, US08-CA02, TS05-CA01 |

---

## Brechas de backend que bloquean Mobile-1b

Estas cinco no se resuelven construyendo el cliente. Exigen una decisión y un cambio en el backend o en la
configuración de Keycloak.

| # | Brecha | CA afectado | Evidencia |
|---|---|---|---|
| 1 | Ningún endpoint publica el texto, la versión ni el hash del consentimiento vigente. El móvil no puede generar un `consentTextHash` válido. | US01-CA01 | `IConsentService` declara `GetCurrentText()` y `GetCurrentVersion()` (`src/Cauce.Application/Common/Interfaces/Identity/IConsentService.cs:13-25`) pero ningún controller los expone |
| 2 | `realm.json` no tiene el audience mapper (`aud=cauce-backend`) ni el default scope `basic` (claim `sub`). Un entorno limpio emite tokens que el backend rechaza. | TS01-CA01 | `infrastructure/keycloak/import/realm.json`: sin sección `clientScopes`, `protocolMappers` ausente, `defaultClientScopes = ["web-origins","profile","roles","email"]` |
| 3 | El backend no expone el bloqueo de cuenta ni el tiempo de espera. | US05-CA02 | `AccountLockedException` mapeada a 423 (`ExceptionHandlingMiddleware.cs:163-164`) con **0 sitios de `throw`**; `KeycloakTokenClient.cs:61-65` colapsa 400 y 401 en `invalid_credentials` |
| 4 | No existe endpoint de renovación de token. El access token dura 900 segundos. | US08-CA02 | Sin acción de refresh en `AuthController.cs`; `KeycloakTokenClient` solo tiene `LoginAsync` y `LogoutAsync` |
| 5 | El enlace del correo de recuperación apunta al backend, que no sirve esa ruta. Sin deep link, el paciente no puede cerrar el flujo desde la app. | US07-CA01, US07-CA02 | `ClientUrlProvider.cs:28-29` arma `{AppBaseUrl}/auth/password-reset?token=...`; `appsettings.Development.json:29` fija `AppBaseUrl = "http://localhost:5074"` |

Brecha adicional, fuera del alcance de los 15 CA de esta matriz: no existe endpoint de canje de código de
invitación posterior al registro (US20-CA02), ni de reenvío del correo de verificación.

---

## Reconciliación con `anexo-oe3-cobertura-ca.md`

El anexo declara **US05 CA02** y **TS01 CA02** como cobertura **full 100 %**
(`docs/traceability/anexo-oe3-cobertura-ca.md:41,57`). La verificación de código encontró que:

- `AccountLockedException` está definida y mapeada a 423, pero **nunca se lanza** (0 sitios de `throw` en
  `src/` y `tests/`).
- `User.RegisterFailedLogin()`, `User.Lock()` e `User.IsLocked()` tienen **0 llamadores en `src/`**.
- El contrato de `/auth/login` **no declara 423** (`AuthController.cs:86-89`).
- **No existe** endpoint que exponga `locked_until`.

### Qué mide realmente el anexo

El propio anexo fija su perspectiva: *"La clasificación se hace desde el backend puro y su capacidad de
integración con un frontend futuro"*, e incluye los CA de "sabor frontend" como full **"cuando el backend
expone el contrato de datos adecuado para que el frontend se vincule directamente"**
(`anexo-oe3-cobertura-ca.md:20-24`).

### Conclusión para TS01-CA02: el anexo NO sobreestima

TS01 CA02 exige tres cosas: que Keycloak bloquee tras cinco fallos, que el evento quede en el audit log con
timestamp e IP, y que el usuario no pueda autenticarse hasta que expire el bloqueo. Las tres se cumplen:

| Exigencia del CA | Estado | Evidencia |
|---|---|---|
| Keycloak bloquea tras 5 fallos | Cumple | `realm.json`: `bruteForceProtected: true`, `failureFactor: 5` |
| Evento en audit log con timestamp e IP | Cumple | `AuditingMiddleware.cs:108` (`AuditActionType.FailedLogin`), `:140-148` (`ipAddress`), `AuditLog.cs:52,68` (`IpAddress`, `OccurredAt`) |
| No puede autenticarse hasta que expire | Cumple | Lo aplica Keycloak |

`DECISIONS-BLOCK-06.md` (DEC-B6-11) y el acta A21 lo confirman: *"realm.json ya tenía la configuración
completa. Sin cambio de código; verificación + acta A21"*. **El anexo mide la configuración de Keycloak más
la auditoría, y eso efectivamente existe.** La calificación es defendible.

### Conclusión para US05-CA02: el anexo SÍ sobreestima

US05 CA02 exige, textualmente, que el sistema *"muestra un mensaje que indica el bloqueo **y el tiempo de
espera**"*. Ese es un CA de "sabor frontend", y por la regla del propio anexo solo cuenta como full **si el
backend expone el contrato de datos adecuado**. No lo expone:

| Dato que el frontend necesita | ¿El backend lo expone? |
|---|---|
| Que la cuenta está bloqueada (y no que la contraseña es incorrecta) | **No.** Keycloak responde 401 y `KeycloakTokenClient.cs:61-65` lo colapsa en `invalid_credentials`, idéntico a una contraseña errónea |
| El tiempo de espera restante | **No.** Ningún endpoint expone `locked_until`; el 423 `account_locked` es código muerto |

Con el contrato actual, **un cliente correctamente implementado no puede cumplir US05 CA02**: no tiene forma
de saber que la cuenta está bloqueada ni cuánto falta para el desbloqueo.

**Veredicto.** `anexo-oe3-cobertura-ca.md` sobreestima US05 CA02. Por su propio criterio metodológico, ese CA
debería figurar como deuda técnica o placeholder, no como full 100 %. La parte de auditoría del CA
(*"registra el evento en el audit log"*) sí se cumple; lo que falta es la parte de contrato hacia el
frontend.

**No se modificó `anexo-oe3-cobertura-ca.md`.** La discrepancia queda documentada aquí para que Trigo decida
si corresponde corregir el anexo antes de la defensa del OE3.

---

## Historial

| Versión | Fecha | Cambios |
|---|---|---|
| 1.0 | 2026-07-13 | Versión inicial. Levantada del código en el tag `v0.6.2-dev-seed` para habilitar Mobile-1b. |
