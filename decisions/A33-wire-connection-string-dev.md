# Acta A33: Wireado de ConnectionStrings:Cauce en Development vía user-secrets

**Estado:** Aprobada
**Fecha:** 2026-07-10
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, config de Development por developer. No toca código ni el contrato de API.

---

## Contexto

Ni `appsettings.json` ni `appsettings.Development.json` contienen `ConnectionStrings:Cauce`. La
convención del proyecto (CONVENTIONS §14) es que Development lo tome de user-secrets y que ningún
secreto se commitee. Con la clave sin setear, la API arrancaba pero fallaba al abrir la conexión a
Postgres. El defecto estaba oculto porque los tests de integración levantan su propio Postgres con
Testcontainers y no dependen de esta clave.

## Decisión

Cada developer setea la connection string en su perfil local:

```
dotnet user-secrets set "ConnectionStrings:Cauce" "Host=localhost;Port=5432;Database=cauce_dev;Username=cauce;Password=<from-.env>" --project src\Cauce.Api
```

La password se lee de `POSTGRES_PASSWORD` en el `.env` del repo `infrastructure` y nunca se commitea.

## Consecuencias

La connection string vive en el perfil de Windows del developer, no en el repo. Depende de A32: el
`UserSecretsId` debe existir primero. Queda registrado como prerequisito 3 en la sección Setup de
`backend/CLAUDE.md`.

## Referencias

- `backend/CONVENTIONS.md`, sección 14 (Configuración y secretos).
- `infrastructure/.env` (`POSTGRES_PASSWORD`).
- Acta [A32](A32-add-user-secrets-id.md).
- `backend/CLAUDE.md`, sección Setup del entorno de desarrollo local.
