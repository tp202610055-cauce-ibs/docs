# Acta A31: Reubicación del script de init de Keycloak a postgres/init

**Estado:** Aprobada
**Fecha:** 2026-07-10
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `infrastructure`. No toca código ni el contrato de API.

---

## Contexto

El archivo `01-create-keycloak-db.sh` vivía en la raíz de `infrastructure/`, pero el
`docker-compose.yml` monta `./postgres/init/` como `/docker-entrypoint-initdb.d` del contenedor
Postgres. Postgres solo ejecuta los scripts de esa carpeta durante el bootstrap de un volumen virgen.
Con el script fuera de ella, un `docker compose down -v` para reseed limpio dejaba a Postgres sin el
rol `keycloak` ni la base `keycloak`, y Keycloak fallaba al conectar en el arranque siguiente.

El stack venía funcionando solo porque alguien había ejecutado el script a mano tiempo atrás y el rol
quedó persistido en el volumen. El defecto estuvo oculto hasta que se ejercitó un `down -v` real
durante la preparación del smoke test.

## Decisión

Mover el archivo a `infrastructure/postgres/init/01-create-keycloak-db.sh` para que Postgres lo
ejecute automáticamente al inicializar un volumen limpio.

## Consecuencias

Cualquier `docker compose down -v` reseedea el rol y la base de Keycloak sin intervención manual. El
cambio vive únicamente en el repo `infrastructure` y ya fue commiteado. Queda registrado como
prerequisito 1 en la sección "Setup del entorno de desarrollo local" de `backend/CLAUDE.md`.

## Referencias

- `infrastructure/postgres/init/01-create-keycloak-db.sh`
- `infrastructure/docker-compose.yml` (montaje de `/docker-entrypoint-initdb.d`)
- `backend/CLAUDE.md`, sección Setup del entorno de desarrollo local.
