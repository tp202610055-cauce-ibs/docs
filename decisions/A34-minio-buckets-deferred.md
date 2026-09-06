# Acta A34: Creación de buckets MinIO diferida (NRE en MinioBucketSeeder)

**Estado:** Aprobada (deuda diferida)
**Fecha:** 2026-07-10
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, capa Infrastructure (`MinioBucketSeeder`). No toca el contrato de API.

---

## Contexto

Al arrancar la API en Development, el `MinioBucketSeeder` lanza `NullReferenceException` al verificar
los buckets `clinical-reports` y `patient-exports`. La excepción proviene de
`Minio.RequestExtensions.ExecuteTaskAsync`. El backend sigue arrancando porque el fallo se captura y
se registra como warning, no detiene el arranque. Solo afecta a US24 (reporte PDF del paciente) y
US25 (export de datos), ambos de Mobile-5.

## Decisión

Diferir el fix a después de Mobile-4. El defecto no bloquea Mobile-1 a Mobile-4, que no tocan MinIO.

## Consecuencias

Antes de Mobile-5, los buckets `clinical-reports` y `patient-exports` deberán crearse a mano vía la
consola de MinIO (`http://localhost:9001`), o bien corregirse el bug del seeder. La deuda queda
listada en la sección "Deuda técnica conocida" de `backend/CLAUDE.md`.

## Referencias

- `backend/src/Cauce.Infrastructure/Persistence/Seeders/MinioBucketSeeder.cs`
- `infrastructure/docker-compose.yml` (contenedor `minio`, buckets `clinical-reports` y `patient-exports`).
- `backend/CLAUDE.md`, sección Deuda técnica conocida.
