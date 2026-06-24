# Decisiones Técnicas — Bloque 3 (Pre-desarrollo)

**Estado:** Aprobadas
**Fecha de aprobación:** 23 de junio de 2026
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repos `backend`, `mobile`, `web-portal`, `infrastructure`

Estas decisiones son la fuente de verdad para cualquier código generado posteriormente. Si una implementación necesita desviarse de cualquiera de ellas, debe escribirse un ADR nuevo (DEC-012 en adelante) que documente la justificación. Hasta entonces, este documento manda.

---

## DEC-B3-01 — Estrategia de tokens OIDC

### Configuración

| Aspecto | Valor | Aplicación |
| --- | --- | --- |
| Access token lifespan | 15 minutos (900 s) | Realm `cauce` global |
| Refresh token lifespan (móvil) | 30 días (2 592 000 s) | Cliente `cauce-mobile` |
| Refresh token lifespan (web) | 8 horas (28 800 s) | Cliente `cauce-web-portal` |
| Refresh token rotation | Activada (`revokeRefreshToken: true`, `refreshTokenMaxReuse: 0`) | Realm `cauce` global |
| Offline tokens | Habilitados solo para `cauce-mobile` (scope `offline_access` opcional) | Cliente `cauce-mobile` |
| SSO session idle timeout | 30 minutos (1800 s) | Realm `cauce` global |
| SSO session max lifespan | 30 días (2 592 000 s) | Realm `cauce` global |

### Justificación

- Access token corto reduce ventana de exposición ante robo de token.
- Refresh token móvil largo porque el dispositivo tiene almacenamiento seguro (`flutter_secure_storage`) y la UX demanda no relogear cada poco tiempo.
- Refresh token web corto porque el navegador del nutricionista es un entorno más expuesto y el caso de uso es jornada laboral.
- Rotation activada para detectar tokens robados: si un atacante usa un refresh token, el siguiente intento del legítimo invalida la cadena.
- Offline tokens solo en móvil para soportar modo offline-first del paciente sin permitir el mismo en navegadores.

### Implementación

Configuración del realm en `infrastructure/keycloak/import/realm.json`, sección `attributes` de cada cliente y campos globales del realm. Ya aplicada al Bloque 2.

---

## DEC-B3-02 — Política CORS

### Configuración

**Orígenes permitidos** (backend `Program.cs` con `AddCors`):

| Origen | Entorno | Justificación |
| --- | --- | --- |
| `http://localhost:5173` | Development | Portal web React con Vite |
| `http://localhost:3000` | Development | Portal web React con CRA (alternativa) |
| `<dominio_produccion>` | Production | Por definir cuando se despliegue el portal |

**Métodos permitidos**: `GET, POST, PUT, PATCH, DELETE, OPTIONS`

**Headers permitidos**: `Authorization, Content-Type, Idempotency-Key, X-Client-Guid`

**Allow credentials**: `true`

**No CORS para móvil**: las apps Flutter nativas no son origen web; llaman directo al backend sin restricción CORS.

### Justificación

- Lista blanca explícita evita ataques CSRF cross-origin.
- Headers limitados al conjunto que realmente se usa, no `*`, por defensa en profundidad.
- Credentials true es necesario si en algún punto usamos cookies HttpOnly para refresh (no decidido aún, pero deja la puerta abierta).

### Implementación

`Cauce.Api/Program.cs`:

```csharp
builder.Services.AddCors(options =>
{
    options.AddPolicy("CaucePortalPolicy", policy =>
    {
        policy.WithOrigins(builder.Configuration["Cors:AllowedOrigins"].Split(','))
              .WithMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
              .WithHeaders("Authorization", "Content-Type", "Idempotency-Key", "X-Client-Guid")
              .AllowCredentials();
    });
});
```

Configuración por entorno vía `appsettings.{Environment}.json` con la lista de orígenes separados por coma.

---

## DEC-B3-03 — Rate limiting

### Configuración

Middleware nativo de ASP.NET Core 9 (`Microsoft.AspNetCore.RateLimiting`).

| Endpoint | Límite | Ventana | Particionado por |
| --- | --- | --- | --- |
| `POST /api/v1/auth/register` | 5 requests | 1 hora | IP del cliente |
| `POST /api/v1/auth/login` | 10 requests | 1 minuto | IP del cliente |
| `POST /api/v1/auth/password-reset/request` | 3 requests | 1 hora | IP del cliente |
| Endpoints autenticados (default) | 60 requests | 1 minuto | `userId` del JWT |
| Endpoints de sync (`POST /api/v1/sync/*`) | 120 requests | 1 minuto | `userId` del JWT |

### Justificación

- Los endpoints públicos de auth son los más atacados (credential stuffing, registro masivo); límites bajos por IP.
- Sync requiere ventana más amplia porque la carga inicial post-onboarding puede ser intensa.
- Particionado por `userId` cuando hay sesión, por IP cuando no.

### Implementación

`Cauce.Api/Program.cs`:

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("auth-register", opt => { opt.PermitLimit = 5;  opt.Window = TimeSpan.FromHours(1); });
    options.AddFixedWindowLimiter("auth-login",    opt => { opt.PermitLimit = 10; opt.Window = TimeSpan.FromMinutes(1); });
    options.AddFixedWindowLimiter("auth-pwreset",  opt => { opt.PermitLimit = 3;  opt.Window = TimeSpan.FromHours(1); });
    options.AddFixedWindowLimiter("default-auth",  opt => { opt.PermitLimit = 60; opt.Window = TimeSpan.FromMinutes(1); });
    options.AddFixedWindowLimiter("sync",          opt => { opt.PermitLimit = 120; opt.Window = TimeSpan.FromMinutes(1); });
});
```

Aplicar con `[EnableRateLimiting("<policy-name>")]` en cada controller/action.

Thresholds se ajustan durante testing si se detecta fricción legítima.

---

## DEC-B3-04 — Idempotency-Key

### Configuración

Endpoints de creación que aceptan registros del móvil llevan header obligatorio:

```
Idempotency-Key: <client_guid>
```

donde `<client_guid>` es el UUID v4 generado en el dispositivo al capturar el dato.

### Endpoints afectados

- `POST /api/v1/meals`
- `POST /api/v1/symptoms`
- `POST /api/v1/clinical-notes`
- `POST /api/v1/recommendations/{id}/feedback`
- `POST /api/v1/assessments/ibs-sss`

### Comportamiento del backend

1. Recibir request con `Idempotency-Key`.
2. Buscar en la tabla correspondiente si ya existe un registro con ese `client_guid` para el paciente autenticado.
3. Si existe:
   - Si los datos del request son idénticos al registro existente → `200 OK` con el recurso ya creado.
   - Si los datos difieren → `409 Conflict` con código `idempotency_mismatch`.
4. Si no existe → procesar normalmente y devolver `201 Created`.

### Justificación

- La red móvil es intermitente; el cliente reintentará envíos sin saber si el primero llegó.
- Sin idempotency, cada retry crea un duplicado.
- Reusar `client_guid` como Idempotency-Key evita una columna extra y mantiene la semántica: un registro lógico, una identidad estable que viaja desde el dispositivo.

### Implementación

Un `IdempotencyAttribute` o filter aplicado por controller, que ejecuta la verificación antes de invocar el handler MediatR.

---

## DEC-B3-05 — API versioning

### Configuración

Versionado en la URL: todas las rutas viven bajo `/api/v{major}/...`.

- **Versión inicial**: `v1`
- **Implementación**: paquete NuGet `Asp.Versioning.Mvc.ApiExplorer`
- **Anotación**: `[ApiVersion("1.0")]` en cada controller
- **Política de versionado**: las versiones mayores rompen contrato; las menores son backward-compatible y no requieren nueva URL.

### Justificación

- Versionado en URL es el más visible y fácil de debuggear (vs. header-based o accept-based).
- Mantener `v1` durante todo el piloto y la primera publicación.
- Cuando llegue `v2` (post-piloto), ambas coexisten hasta que se deprecate `v1` con anuncio formal.

### Implementación

`Cauce.Api/Program.cs`:

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = new UrlSegmentApiVersionReader();
});
```

Todos los controllers heredan de una `BaseController` que ya trae `[ApiVersion("1.0")]` y `[Route("api/v{version:apiVersion}/[controller]")]`.

---

## DEC-B3-06 — Asociación temporal síntoma↔comida (ventana 4h)

### Configuración

Cálculo del campo `symptoms.associated_meal_id` ocurre **en el cliente móvil al guardar el síntoma localmente**.

### Algoritmo en el cliente

1. Al persistir un nuevo `Symptom` en SQLite local:
2. Buscar la última `Meal` del mismo paciente con `client_created_at` en el intervalo `[symptom.client_created_at - 4h, symptom.client_created_at]`.
3. Si existe → `associated_meal_id = meal.client_guid` y `has_meal_association = true`.
4. Si no existe → `associated_meal_id = null` y `has_meal_association = false`.

### Validación en el backend (defensa en profundidad)

Al sincronizar, el endpoint `POST /api/v1/sync/symptoms` revalida:

1. Si el `associated_meal_id` apunta a una `Meal` existente del paciente:
   - Si el delta temporal entre `symptom.client_created_at` y `meal.client_created_at` cae dentro de las 4h → aceptar.
   - Si el delta excede 4h → setear `associated_meal_id = null` y `has_meal_association = false`. **No rechazar el síntoma completo**, solo limpiar la asociación incorrecta.
2. Si el `associated_meal_id` no existe en backend (todavía no sincronizó la comida) → reintentar la asociación en el próximo sync batch que incluya esa comida.

### Justificación clínica

- Ventana de 4h fundamentada en literatura: Monash University (2019) y Ford et al. (2024, *Gut*).
- 24h sería clínicamente inválido para correlación causal alimentaria.

### Justificación técnica

- Cliente tiene contexto local sin depender de red.
- Backend revalida como capa adicional ante bugs del cliente.
- Si el servidor detecta tasa alta de asociaciones inválidas en logs, se diagnostica como bug del cliente sin requerir nueva versión emergente.

---

## DEC-B3-07 — Estrategia de seeders

### Configuración

Tres seeders idempotentes en `Cauce.Infrastructure/Persistence/Seeders/`, más uno de development.

| Seeder | Tabla | Fuente | Cuándo se ejecuta |
| --- | --- | --- | --- |
| `UserRolesSeeder` | `user_roles` | Catálogo cerrado en código | Cada arranque (idempotente) |
| `AllergiesSeeder` | `allergies` | Catálogo cerrado en código (a definir cuando se implemente módulo) | Cada arranque (idempotente) |
| `FoodItemsSeeder` | `food_items` | CSV de TPCA-CENAN 2017 (928 alimentos) | Una sola vez vía CLI command |
| `DevAdminSeeder` | Keycloak + `users` + `patient_profiles` | Hardcoded en código, solo si `ASPNETCORE_ENVIRONMENT == "Development"` | Cada arranque en Development |

### Modos de ejecución

1. **Automático en Development**: en `Program.cs`, si environment es `Development`, ejecuta todos los seeders al startup.
2. **CLI command para Production**: `dotnet run --project src/Cauce.Api -- seed <nombre_seeder>` para ejecución controlada.

### Idempotencia

Cada seeder verifica si el dato ya existe antes de insertarlo. Reejecutar el seeder no duplica filas ni lanza errores.

### Fuente del catálogo de alimentos

CSV generado a partir de las **Tablas Peruanas de Composición de Alimentos del INS / CENAN (2017)**. Tarea aparte:

- Responsable: Trigo o Mirian (a coordinar).
- Formato: CSV con columnas `name`, `category`, `calories_per_100g`, `protein_g_per_100g`, `carbs_g_per_100g`, `fiber_g_per_100g`, `fat_g_per_100g`, `fodmap_level`, `fodmap_tags`, `is_peruvian`.
- Clasificación FODMAP: cruzar con Liljebo et al. 2020 (PMC7499970) para los 1 060 ítems clasificados ahí; el resto queda como `unknown` provisional o se clasifica por similitud.
- Ubicación del CSV: `backend/src/Cauce.Infrastructure/Persistence/Seeders/Data/food_items_seed.csv` (versionado en git porque es referencia clínica).

### DevAdminSeeder — detalle

Crea un usuario nutricionista en Keycloak vía Admin API + fila en `users` + sin `patient_profile` (no aplica). Credenciales hardcoded: email `admin@cauce.local`, password `Admin12345`. **NUNCA** ejecutar en Production.

---

## DEC-B3-08 — Provisioning del modelo ONNX

### Configuración

Dos mecanismos coexistentes para subir un nuevo modelo a producción:

#### Mecanismo 1 — CLI command (Production)

```bash
dotnet run --project src/Cauce.Api -- seed model \
  --file ./model_v1.0.0.onnx \
  --version 1.0.0 \
  --hash <sha256_del_archivo> \
  --notes "Modelo entrenado con dataset sintético v1, accuracy 0.84"
```

Acciones:

1. Calcula hash SHA-256 del archivo y compara con el `--hash` provisto.
2. Sube el archivo a MinIO en el bucket `cauce-models/` con clave `model_v{version}.onnx`.
3. Inserta fila en `model_versions` con `active = false`.
4. Imprime el `model_id` resultante.

Activación posterior con:

```bash
dotnet run --project src/Cauce.Api -- activate model --version 1.0.0
```

#### Mecanismo 2 — Endpoint admin (Development y testing)

```http
POST /api/v1/admin/models
X-Admin-Api-Key: <api_key_del_env>
Content-Type: multipart/form-data

file: <binary .onnx>
version: 1.0.0
hash: <sha256>
notes: ...
```

Mismo flujo interno que el CLI, pero accesible vía HTTP. Protegido únicamente por el header `X-Admin-Api-Key` que vive en `Cauce.Api/.env` como `ADMIN_API_KEY`.

#### Activación transaccional

Activar un modelo implica una transacción Postgres:

```sql
BEGIN;
  UPDATE model_versions SET active = false WHERE active = true;
  UPDATE model_versions SET active = true WHERE version = '1.0.0';
COMMIT;
```

Garantiza que en ningún momento haya dos modelos activos ni cero modelos activos durante el switch.

### Justificación

- CLI es seguro para producción (acceso por SSH al servidor del hospital).
- Endpoint admin es para development rápido sin exponer SSH.
- API key estática es suficiente para piloto; en post-piloto se reemplaza por OIDC con rol `admin`.

---

## DEC-B3-09 — División de auditoría (middleware vs triggers BD)

### Configuración

| `action_type` | Mecanismo de captura | Tabla afectada o evento origen |
| --- | --- | --- |
| `LOGIN` | Event listener de Keycloak → middleware `AuditMiddleware` | Evento `LOGIN` del Keycloak event stream |
| `LOGOUT` | Event listener de Keycloak → middleware `AuditMiddleware` | Evento `LOGOUT` |
| `FAILED_LOGIN` | Event listener de Keycloak → middleware `AuditMiddleware` | Evento `LOGIN_ERROR` |
| `ACCOUNT_LOCKED` | Event listener de Keycloak → middleware `AuditMiddleware` | Evento `USER_DISABLED_BY_PERMANENT_LOCKOUT` o equivalente |
| `INSERT/UPDATE/DELETE` sobre `patient_profiles` | Trigger AFTER en Postgres | Tabla `patient_profiles` |
| `INSERT/UPDATE/DELETE` sobre `recommendations` | Trigger AFTER en Postgres | Tabla `recommendations` |
| `INSERT` sobre `consent_records` | Trigger AFTER en Postgres | Tabla `consent_records` |
| `APPROVE`, `REJECT` sobre `recommendations` | Middleware aplicativo (captura antes de persistir) | Endpoints HITL del backend |
| `DELIVER` sobre `recommendations` | Middleware aplicativo | Endpoint que marca `Delivered` al sincronizar al móvil |
| `EXPORT_PDF` | Middleware aplicativo | Endpoint de generación de reportes |
| `VIEW_PATIENT_RECORD` | Middleware aplicativo | Endpoint del portal nutricionista que abre historia clínica |

### Inmutabilidad de `audit_logs`

Implementación obligatoria en migración EF Core inicial:

```sql
CREATE OR REPLACE FUNCTION reject_audit_log_modification()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs is immutable: % operations are not allowed', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_audit_update
  BEFORE UPDATE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION reject_audit_log_modification();

CREATE TRIGGER prevent_audit_delete
  BEFORE DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION reject_audit_log_modification();
```

Ningún código de aplicación puede modificar o eliminar registros de `audit_logs`. Las únicas operaciones permitidas son INSERT y SELECT.

### Justificación

- **Triggers BD** garantizan captura aunque alguien modifique la BD por fuera del backend (ej. acceso directo del DBA con `psql`).
- **Middleware aplicativo** captura eventos con metadata adicional que el trigger no ve (`reviewed_by`, `notes`, `recommendation_diff`).
- **Sin solapamiento**: cada `action_type` tiene un único origen claro.
- **Inmutabilidad a nivel BD** es defensa final contra repudio: incluso un atacante con credenciales de DB no puede borrar la evidencia.

### Cumplimiento normativo

Esta división satisface el artículo 9 de la Ley N° 29733 (integridad de los datos personales) y el principio de no repudio del consentimiento informado registrado en `consent_records`.

---

## Pendientes derivados de este Bloque

Estas son tareas explícitas que deben ejecutarse durante el desarrollo:

1. **CSV de food_items** desde TPCA-CENAN: tarea aparte, coordinar con Mirian o ejecutar en paralelo. No bloquea el desarrollo del backend hasta el módulo `ClinicalRegistry`.
2. **Catálogo cerrado de allergies**: definir lista exacta cuando se implemente el módulo `Patients`. Sugerencia: gluten, lactosa, frutos secos, mariscos, huevo, soya, pescado, sulfitos, leguminosas, fructosa (relevantes para SII).
3. **Dominio de producción del portal nutricionista**: definir cuando el portal esté listo para deployment. Hasta entonces, `appsettings.Production.json` queda con placeholder.
4. **API key del endpoint admin de modelos**: generar un valor aleatorio fuerte y colocarlo en `Cauce.Api/.env` como `ADMIN_API_KEY` cuando se implemente el módulo `Recommendations`.

---

## Trazabilidad con historias de usuario

| Decisión | Historias técnicas relacionadas |
| --- | --- |
| DEC-B3-01 (Tokens) | TS-01 (completa la parte de configuración del IdP, validación queda al backend) |
| DEC-B3-02 (CORS) | TS-02 (a definir cuando se trabaje API gateway) |
| DEC-B3-03 (Rate limiting) | TS-01 (CA02 bloqueo por intentos parte de esta decisión) |
| DEC-B3-04 (Idempotency-Key) | TS-04 (sincronización offline-first) |
| DEC-B3-05 (Versioning) | Transversal a todas las TS |
| DEC-B3-06 (Ventana 4h) | TS-05 (motor de recomendaciones — la asociación es input al motor) |
| DEC-B3-07 (Seeders) | TS-06 (catálogo de alimentos peruanos) |
| DEC-B3-08 (ONNX provisioning) | TS-07 (integración ONNX Runtime — tolerancia <0.001 vs Python) |
| DEC-B3-09 (Auditoría) | TS-01 (CA02 parte de esta decisión), TS-03 (auditoría HITL) |

---

## Cambios futuros

Si alguna decisión cambia, **no editar este documento**. Crear un ADR nuevo (`docs/decisions/DEC-012-XXX.md`) que documente:

- Qué decisión cambia.
- Por qué cambia.
- Qué código se ve afectado.
- Plan de migración.

Este documento es la baseline del Bloque 3 y debe permanecer estable como referencia histórica.
