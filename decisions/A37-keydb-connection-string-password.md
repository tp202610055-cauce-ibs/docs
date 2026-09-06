# Acta A37: Password de KeyDB faltante en el connection string del API

**Estado:** Aprobada
**Fecha:** 2026-07-10
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, config de Development por developer. No toca código ni el contrato de API.

---

## Contexto

KeyDB corre con `--requirepass ${KEYDB_PASSWORD}` (docker-compose de `infrastructure`), pero el
`appsettings.Development.json` traía `KeyDb:ConnectionString = "localhost:6379"` sin password. El cliente
`StackExchange.Redis` fallaba la autenticación (NOAUTH); como el multiplexer se registra con
`AbortOnConnectFail = false` (tolerancia a fallos del piloto), degradaba en fail-open silencioso: el
arranque no se rompía y el `IdempotencyBehavior` dejaba de cachear. Firma exacta del defecto:

- POST idempotente de 6 a 12 s por intento (timeout de conexión a KeyDB en cada roundtrip de get y set).
- Replay con la misma `Idempotency-Key` devolvía 500 en vez de 200: el store no había cacheado, el segundo
  intento reintentaba el INSERT y chocaba con la constraint única de `client_guid` en `meals`.
- KeyDB no contenía ninguna clave `idempotency:*`.

Ese patrón (POST inicial de 6 a 12 s más replay 500 por violación de constraint) es el fingerprint canónico
de un fail-open silencioso de KeyDB o Redis, y conviene recordarlo como marcador de defectos similares durante el piloto.

## Decisión

Setear en user-secrets del developer:

```
dotnet user-secrets set "KeyDb:ConnectionString" "localhost:6379,password=<from-.env>" --project src\Cauce.Api
```

El password se lee de `KEYDB_PASSWORD` en el `.env` de `infrastructure`. Nunca commitear en `appsettings`
ni en user-secrets del repo.

## Consecuencias

Verificadas post-fix: POST idempotente en 0.70 s, replay en 0.02 s con el mismo `mealId`, y KeyDB con las
claves `idempotency:*` esperadas. Depende de A32 (`UserSecretsId`). Prerequisito 3 en la sección Setup de
`backend/CLAUDE.md`.

## Referencias

- `backend/src/Cauce.Infrastructure/DependencyInjection.cs` (multiplexer, `AbortOnConnectFail=false`).
- `backend/src/Cauce.Application/Common/Behaviors/IdempotencyBehavior.cs`.
- `infrastructure/.env` (`KEYDB_PASSWORD`).
- `backend/CLAUDE.md`, sección Setup del entorno de desarrollo local.
