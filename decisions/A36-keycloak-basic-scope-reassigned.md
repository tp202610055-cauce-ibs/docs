# Acta A36: Reasignación del default scope basic a los clientes OIDC

**Estado:** Aprobada
**Fecha:** 2026-07-10
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Configuración del realm `cauce` en Keycloak. No toca código ni el contrato de API.

---

## Contexto

Al reconfigurar los default client scopes de `cauce-mobile` para agregar `cauce-backend-audience`
(A35), se perdió el default scope `basic`. En Keycloak 25 el mapper `sub` (Subject) vive dentro del
scope `basic`. Sin él, el access token no incluye el claim `sub`. El backend resuelve el usuario local
en `CurrentUserService.UserId` (lee `sub`) y luego `FindByKeycloakIdAsync(sub)`; sin `sub`, todo
endpoint que resuelve usuario lanza `UnauthorizedAccessException`, mapeada a 403. El endpoint `/foods`
seguía respondiendo porque solo exige `[Authorize]` sin resolver usuario local. Los tests de
integración inyectan `sub` directo con `TestJwtBuilder`, así que el defecto estaba oculto.

## Decisión

Reasignar el scope `basic` como default a `cauce-mobile` y `cauce-web-portal` desde la consola de
administración de Keycloak.

## Consecuencias

El token pasa a traer `sub` y todos los endpoints con policy `Patient` funcionan. Verificado: el `sub`
del token (`b8ebd09c-3bb3-4e7b-90dd-a55124bae0fd`) coincide con el `keycloak_id` del paciente demo en
la tabla `users`. Toda futura importación de `realm.json` debe verificar que ambos clientes tengan
`basic` y `cauce-backend-audience` en sus default scopes. Queda registrado como prerequisito 4 en la
sección Setup de `backend/CLAUDE.md`.

## Referencias

- Keycloak realm `cauce`, default client scopes de `cauce-mobile` y `cauce-web-portal`.
- `backend/src/Cauce.Infrastructure/Identity/CurrentUserService.cs`.
- Acta [A35](A35-keycloak-audience-mapper.md).
- `backend/CLAUDE.md`, sección Setup del entorno de desarrollo local.
