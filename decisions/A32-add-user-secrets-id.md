# Acta A32: Declaración de UserSecretsId en Cauce.Api.csproj

**Estado:** Aprobada
**Fecha:** 2026-07-10
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, proyecto `Cauce.Api`, config de Development. No toca el contrato de API.

---

## Contexto

El `Cauce.Api.csproj` no declaraba `<UserSecretsId>`. Los tests de integración con Testcontainers no
usan user-secrets (inyectan su configuración vía `CustomWebApplicationFactory`), así que el faltante
estaba oculto. Al intentar correr la API contra la base real de dev, `dotnet user-secrets list`
fallaba y `ConnectionStrings:Cauce` quedaba vacío, de modo que la API arrancaba pero no abría
conexión a Postgres.

## Decisión

Agregar `<UserSecretsId>` con un GUID único al PropertyGroup principal del `Cauce.Api.csproj`. Esto
habilita la feature de `dotnet user-secrets` para el proyecto.

## Consecuencias

Development toma la connection string y demás secretos del store de user-secrets local, por developer
y por máquina. El piloto y Production usan variables de entorno o un secret manager. En Production el
`UserSecretsId` no tiene efecto en runtime, es solo declarativo para la herramienta de dev. Habilita
los secretos de A33 y A37. Queda registrado como prerequisito 2 en la sección Setup de
`backend/CLAUDE.md`.

## Referencias

- `backend/src/Cauce.Api/Cauce.Api.csproj`
- `backend/CONVENTIONS.md`, sección 14.2 (User Secrets).
- Actas [A33](A33-wire-connection-string-dev.md) y [A37](A37-keydb-connection-string-password.md).
- `backend/CLAUDE.md`, sección Setup del entorno de desarrollo local.
