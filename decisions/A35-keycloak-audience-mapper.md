# Acta A35: Client scope de audiencia en Keycloak (cauce-backend-audience)

**Estado:** Aprobada, con Nota de persistencia del 2026-09-05
**Fecha:** 2026-07-10
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Configuración del realm `cauce` en Keycloak. No toca código ni el contrato de API.

---

## Contexto

Los tokens JWT que Keycloak emitía para `cauce-mobile` traían `aud: "account"`. El backend valida
`Audience = "cauce-backend"` con `ValidateAudience = true` en `Program.cs`. El mismatch de audiencia
rechazaba todo token real con 401 en los endpoints protegidos. Los 143 tests de integración usan
`TestJwtBuilder`, que firma tokens locales con `aud = cauce-backend` ya correcto, por lo que la
validación de audiencia nunca se ejercitó en runtime hasta pegarle con un token real de Keycloak.

## Decisión

Crear un client scope `cauce-backend-audience` en el realm `cauce` con un protocol mapper tipo
Audience (Included Client Audience = `cauce-backend`, Add to access token = ON). Asignarlo como
default scope a `cauce-mobile` y a `cauce-web-portal`.

## Consecuencias

El token pasa a traer `aud: ["cauce-backend", "account"]` y supera la validación del backend. El
cambio es configuración manual de la consola de Keycloak, no se reejecuta desde `realm.json`. Toda
futura importación de `realm.json` debe verificar la presencia de este scope en ambos clientes. Queda
registrado como prerequisito 4 en la sección Setup de `backend/CLAUDE.md`.

## Nota de persistencia (2026-09-05)

La decisión sigue vigente. Cambia el **mecanismo con el que se persiste**, y la divergencia respecto
del cuerpo del acta es deliberada. La pide explícitamente
[`ESTADO-GAPS-BACKEND.md`](../../backend/docs/verificacion/ESTADO-GAPS-BACKEND.md) al cerrar el gap 7.

**Lo que se descubrió.** Declarar la clave `clientScopes` en un realm import **no fusiona con los
client scopes built-in de Keycloak: los reemplaza**. Un `realm.json` que declaraba únicamente
`cauce-backend-audience` importó con `Realm 'cauce' imported` y cero errores en los logs, y produjo un
realm con **2 client scopes en vez de 12**, sin `basic`, sin `profile` y sin `email`. Eso reintroducía
el defecto del acta [A36](A36-keycloak-basic-scope-reassigned.md) y lo agravaba, en silencio. El
enfoque que parecía natural habría sido peor que no hacer nada.

**Cómo quedó persistido.** El `realm.json` vigente (`infrastructure`, commit `7782072`) **no declara
`clientScopes`**. En su lugar:

| Mecanismo del acta | Mecanismo persistido |
| --- | --- |
| Client scope compartido `cauce-backend-audience`, asignado como default a los dos clientes | Un protocol mapper `oidc-audience-mapper` llamado `add-cauce-backend-audience`, declarado **dentro del bloque `protocolMappers` de cada cliente**: una vez en `cauce-mobile` y otra en `cauce-web-portal` |
| `basic` asignado desde consola (acta A36) | `basic` viaja en el arreglo `defaultClientScopes` de ambos clientes, junto con `web-origins`, `profile`, `roles` y `email` |

El efecto sobre el token es idéntico al que describe el acta: `aud: ["cauce-backend", "account"]`, y
el claim `sub` presente. Cambia dónde vive la configuración, no qué produce.

**Consecuencia práctica.** El prerequisito 4 de la sección Setup de `backend/CLAUDE.md` deja de ser
una tarea manual de consola tras cada `docker compose down -v`: el import del realm ya lo trae. La
verificación posterior al import sigue siendo obligatoria, ahora sobre los `protocolMappers` de cada
cliente en vez de sobre la lista de client scopes del realm.

**Lo que falta.** El `realm.json` se validó importándolo en un contenedor Keycloak 25 efímero con base
H2, con tres checks explícitos: los scopes built-in se crean solos, `basic` se resuelve por nombre en
ambos clientes, y un token real trae `aud=cauce-backend` y `sub`. Falta una **ventana de reset
controlado del stack real** (bajar Keycloak, subir con el realm nuevo sobre Postgres, smoke con el
paciente demo) antes de dar el gap 7 por cerrado sin reservas. H2 y Postgres tienen alta paridad en
imports de realm, no paridad total.

## Referencias

- Keycloak realm `cauce`, client scope `cauce-backend-audience`.
- `backend/src/Cauce.Api/Program.cs` (validación de audiencia).
- Acta [A36](A36-keycloak-basic-scope-reassigned.md).
- `backend/CLAUDE.md`, sección Setup del entorno de desarrollo local.
- `infrastructure/keycloak/import/realm.json`, commit `7782072` (persistencia de A35 y A36).
- [`ESTADO-GAPS-BACKEND.md`](../../backend/docs/verificacion/ESTADO-GAPS-BACKEND.md), gap 7.
