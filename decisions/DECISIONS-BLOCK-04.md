# Decisiones Técnicas — Bloque 4 (Módulo Recommendations)

**Estado:** Aprobadas
**Fecha de aprobación:** 30 de junio de 2026
**Aprobado por:** Flavio Eduardo Trigueros Chumacero
**Aplicabilidad:** Repo `backend`, módulo `Recommendations` (capas Domain, Application, Infrastructure, Api y tests)

Estas decisiones son la fuente de verdad para el módulo de recomendaciones. Si una implementación necesita desviarse, debe escribirse un ADR nuevo que documente la justificación. Hasta entonces, este documento manda. Complementa —no reemplaza— a `DECISIONS-BLOCK-01.md`.

> **Nota sobre numeración.** El prompt de origen del módulo etiqueta sus decisiones como `DEC-B4-XX`. Se conserva esa numeración aquí por trazabilidad con el Trabajo de Investigación, aunque el archivo precedente sea `DECISIONS-BLOCK-01.md` (los bloques 2 y 3 no llegaron a documentarse como archivo; su fuente de verdad es el código de los módulos Identity, Patients y ClinicalRegistry).

---

## DEC-B4-01 — Motor con abstracción `IRecommendationEngine` + implementación inicial por regla FODMAP

### Contexto

El modelo XGBoost entrenado por Mirian Contreras aún no está exportado a ONNX. No hay garantía de timing. El sistema debe ser funcional desde el día uno.

### Decisión

El módulo expone la abstracción `IRecommendationEngine` en `Cauce.Application/Common/Interfaces/Recommendations/`. La implementación por default es `FodmapRuleRecommendationEngine` (`Cauce.Infrastructure/Recommendations/Engines/`), basada en la fórmula derivada del dataset de Mirian:

```
score = clamp(0.127 + 0.128·oligos + 0.095·fructosa + 0.086·polioles + 0.105·lactosa + 0.00055·cantidad_g, 0, 1)
```

Si las cuatro columnas FODMAP granulares están en 0 (catálogo no enriquecido), se cae a una heurística por `FodmapLevel` (`High`→0.80, `Moderate`→0.50, `Low`→0.25). Se incluye `OnnxRecommendationEngine` con la misma firma que lanza `NotImplementedException` en el constructor, como contract test del DI cuando llegue el modelo.

La selección se hace por configuración `Recommendations:EngineKind` ∈ {`Rule` (default), `Onnx`} en el registro de DI.

### Consecuencias

El sistema funciona sin esperar a Mirian. Cuando el `.onnx` esté disponible, el cambio es de configuración + una sola clase, sin afectar el resto del módulo. Las recomendaciones generadas con la regla quedan trazables vía `ModelVersion` `rule-v1.0.0`.

---

## DEC-B4-02 — Trigger de generación por endpoint API explícito

### Decisión

La generación se dispara por `POST /api/v1/recommendations` invocado por el paciente desde la app móvil. No hay scheduler en este prompt; el worker de generación periódica queda para Prompt 5.

### Consecuencias

No se requiere Hangfire/Quartz/`IHostedService` en Prompt 4. Reduce complejidad y permite cerrar el módulo sin dependencias adicionales.

---

## DEC-B4-03 — Conjunto de candidatos: ventana de consumo del paciente

### Decisión

El motor evalúa los alimentos consumidos en los últimos `Recommendations:CandidateFoodsWindowDays` días (default 14). Si hay menos de `Recommendations:MinCandidateFoodsCount` alimentos distintos (default 5), la ventana se expande a 30 días. Si aún así no llega al mínimo, el endpoint responde **422** con código `insufficient_clinical_history`.

### Consecuencias

Las recomendaciones son sobre la dieta real del paciente, no sobre el catálogo abstracto. Costo computacional acotado (5 a 30 alimentos por inferencia). `IPatientClinicalHistoryReader.GetCandidateFoodsAsync(patientId, windowDays, ct)` agrupa por alimento del catálogo (solo `meal_items` con `food_id`, alimentos activos), devolviendo cantidad promedio consumida.

> **Nota de implementación.** `MealItem` persiste `Quantity` + `Unit` (gramos, tazas, unidades, onzas, cucharadas), no gramos puros. El campo `CandidateFood.QuantityGrams` se aproxima con el promedio de `Quantity` de los ítems de catálogo. Es una aproximación documentada: el coeficiente de cantidad de la regla (0.00055) tiene impacto marginal, y la regla es un placeholder hasta ONNX.

---

## DEC-B4-04 — Auto-aprobación deshabilitada por default en piloto

### Decisión

El sistema se entrega con `Recommendations:AutoApprovalEnabled = false`. Toda recomendación generada pasa por revisión humana antes de entregarse, sin excepción.

### Justificación

El modelo actual (regla FODMAP) tiene recall ~59% sobre datos sintéticos; el comité de ética del piloto típicamente exige revisión humana exhaustiva durante validación clínica; el HITL es la línea legal entre "app de bienestar" y ejercicio ilegal de la medicina (Ley 26842).

### Consecuencias

`AutoApprovalGuard.Evaluate` retorna `false` siempre cuando `AutoApprovalEnabled = false`. El campo `recommendations.auto_approved` será siempre `false` durante el piloto. `confidence_score` se persiste igual para análisis estadístico. La activación es decisión del comité de ética del Kaelín, vía configuración + redespliegue, sin tocar código.

---

## DEC-B4-05 — Criterios de no-auto-aprobar cuando el feature flag esté activo

### Decisión

Cuando `AutoApprovalEnabled = true`, `AutoApprovalGuard` exige:

- **DEC-B4-05.a** `confidence_score >= Recommendations:AutoApprovalThreshold` (default 0.95).
- **DEC-B4-05.b** items con `ActionType = Avoid` `<= Recommendations:MaxAvoidItemsForAutoApproval` (default 3).

Si alguno falla, la recomendación va a `PendingReview`. El criterio "cambio calórico > 20%" (DEC-B4-05.c) se difiere por complejidad metodológica; DEC-B4-05.b cubre buena parte del mismo riesgo.

---

## DEC-B4-06 — Expiración 72h con transición on-read

### Decisión

`recommendations.expires_at` se setea al crear con `generated_at + Recommendations:ExpirationWindowHours` (default 72). La transición a `Expired` se ejecuta **on-read**: cualquier query dirigida al paciente que retorne una recomendación con `expires_at < UtcNow` y estado en {`Generated`, `PendingReview`, `Approved` no entregado} ejecuta la transición en la misma transacción.

### Excepción (adenda de revisión Prompt 4, ver aclaración #3)

`ListPendingReviewForNutritionist` **no** ejecuta `Expire` on-read: filtra por `Status = PendingReview AND ExpiresAt > now` en modo solo-lectura. Las recomendaciones vencidas en `PendingReview` quedan como zombies hasta que el worker de barrido del Prompt 5 las procese. Justificación: en piloto (n=20–50) el volumen es marginal y forzar UPDATEs en un listado paginado añade complejidad sin ganancia (el paciente nunca ve una expirada porque sus queries sí aplican la transición).

### Consecuencias

No se requiere worker programado en este prompt. El paciente nunca ve una recomendación expirada. Las expiradas se conservan para trazabilidad.

---

## DEC-B4-07 — Orquestador LLM con Ollama y fallback de plantilla

### Decisión

`IExplanationOrchestrator` con dos componentes en Infrastructure:

- `OllamaExplanationOrchestrator`: `HttpClient` tipado a `Recommendations:Ollama:Endpoint` (default `http://ollama:11434/api/generate`), timeout `Recommendations:Ollama:TimeoutSeconds` (default 15), modelo `Recommendations:Ollama:Model` (default `llama3.1:8b-instruct-q4_K_M`).
- `FallbackExplanationProvider`: plantilla estática en español que enumera los items.

**Flujo:** llamar a Ollama; si responde dentro del timeout y pasa `RecommendationGuardrailsValidator` → persistir con `explanation_source = LlmGenerated`. Si falla en cualquier punto (timeout, 5xx, guardrail) → `FallbackExplanationProvider` con `explanation_source = Fallback`.

**Guardrails** (`RecommendationGuardrailsValidator`): frases clínicas prohibidas (`diagnóstico|curar|garantizar|síndrome|enfermedad`), certeza absoluta (`siempre|nunca|sin duda|definitivamente`), causalidad directa (`te causa|te va a causar|te genera síntomas`); longitud 80–500; heurística de español (≥3 marcadores funcionales).

**Prompt** (`RecommendationPromptTemplate`): ver aclaración #2 — cada ítem se renderiza como `- {FoodName} ({ActionType en español}): {Reasoning}`, omitiendo el reasoning si está vacío y truncándolo a 117+"…" si supera 120 caracteres. `ActionType` se traduce a evitar/reducir/incorporar/sustituir.

---

## DEC-B4-08 — Extensión de `food_items` con columnas FODMAP granulares

### Decisión

El módulo agrega vía migración EF Core 4 columnas a `food_items` (módulo ClinicalRegistry): `oligos_level`, `fructose_level`, `polyols_level`, `lactose_level`, todas `SMALLINT NOT NULL DEFAULT 0` con CHECK `BETWEEN 0 AND 2`.

### Excepción cross-module documentada

Es la única excepción al principio de "no tocar módulos previos" en este prompt, justificada porque la extensión es aditiva (default 0), no rompe tests de ClinicalRegistry, y la alternativa (tabla separada) introduce JOIN obligatorio sin ganancia. Cambios: 4 propiedades `byte` de solo lectura en `FoodItem`, su mapeo en `FoodItemConfiguration` con CHECK constraints. El seeder de Prompt 3 no se modifica; los registros existentes quedan en 0. El enriquecimiento clínico es tarea pre-piloto (ver "Deuda técnica conocida" en `CLAUDE.md`).

---

## DEC-B4-09 — Allergy filter como guardrail duro pre-inferencia

### Decisión

Antes de invocar al motor, el caso de uso filtra los candidatos contra las alergias declaradas del paciente. Los alimentos detectados como alérgenos se excluyen del conjunto **antes** de la inferencia, no después. Es no negociable y se valida con tests dedicados.

`IPatientAllergyReader.GetAllergyFoodIdsAsync(patientId, ct)` retorna el `HashSet<Guid>` de food ids prohibidos. El filtro se aplica sobre los candidatos y, por construcción, ningún alimento detectado como alérgeno puede aparecer como `RecommendationItem.FoodId` ni como `RecommendationItem.SubstituteFoodId`.

> La **forma de detección** cambia respecto del prompt original (ver DEC-B4-14): el esquema no liga `PatientAllergy` a un `food_id`, por lo que la detección es heurística. El guardrail clínico es idéntico en intención.

---

## DEC-B4-10 — Seeder de `ModelVersion` para regla v1.0.0

### Decisión

Solo en entorno de desarrollo, `RecommendationsModelVersionsSeeder` inserta (idempotente) un registro `rule-v1.0.0` con `is_active = true`, `model_hash` derivado del `Descriptor` del motor, y `performance_metrics` (jsonb) con las métricas replicadas del notebook de Mirian y un disclaimer aclarando que el motor productivo es la regla, no el XGBoost. En producción, la inserción es vía script administrativo out-of-band.

El `model_hash` se computa como SHA-256 de una constante versionada `RULE_VERSION_STRING` dentro del motor (no se lee el archivo fuente en runtime, por portabilidad). Si la fórmula cambia, se actualiza la constante y el hash refleja el cambio.

---

## DEC-B4-11 — Idempotencia en mutaciones críticas

### Decisión

Los endpoints `POST /recommendations`, `.../{id}/feedback`, `.../{id}/approve`, `.../{id}/reject`, `.../{id}/deliver` requieren header `Idempotency-Key` (UUID v4). Se gestiona vía el `IdempotencyBehavior` existente (KeyDB, hash SHA-256 del payload, DEC-B3-04). Replay con payload idéntico → 200 con la respuesta cacheada; replay con payload distinto → **409** `idempotency_mismatch`.

### Implementación (adaptada al repo, acta A2)

Los comandos implementan el marcador `IIdempotentCommand` exponiendo `ClientGuid`, que el controller obtiene del header `Idempotency-Key`. No hay un campo `IdempotencyKey` separado.

---

## DEC-B4-12 — Authorization

### Decisión original

Dos validaciones de acceso por recurso: el paciente solo opera sobre recomendaciones propias; el nutricionista solo sobre recomendaciones de pacientes asignados. Falla → **403** sin filtrar información del recurso.

### Implementación (acta A8) — validación en handler

Por decisión de Flavio en la sesión de revisión, la autorización por recurso **no** se implementa como resource-based authorization handlers de ASP.NET. Se replica el patrón establecido en el backend: `[Authorize(Policy = "Patient"|"Nutritionist")]` por rol a nivel controller + validación de ownership/asignación **dentro del handler**, resolviendo la identidad local desde el JWT (`ICurrentUserService.UserId` → `IUserRepository.FindByKeycloakIdAsync` → check de rol). La falla lanza `RecommendationAccessDeniedException` → 403 sin leak. El intent de DEC-B4-12 se mantiene; cambia el mecanismo.

---

## DEC-B4-13 — Selección de sustituto para items con ActionType `Avoid`

**Contexto**: la traducción de scores a `ActionType` mediante los umbrales `AvoidThreshold` y `ReduceThreshold` produce items en cuatro acciones posibles (`Suggest`, `Reduce`, `Avoid`, `Substitute`), pero el prompt original no especifica bajo qué condiciones un item destinado a `Avoid` se eleva a `Substitute` ni cómo se elige el alimento sustituto. Esta decisión cierra ese gap.

**Decisión**: para cada item resultante en `ActionType.Avoid`, el handler de `GenerateRecommendationCommand` ejecuta el siguiente algoritmo de búsqueda de sustituto sobre el conjunto de candidatos restantes (es decir, el conjunto post-filtro de alergias, excluyendo el item original):

1. Filtrar candidatos por `Category == itemOriginal.Category`.
2. Filtrar candidatos por `SymptomProbability < ReduceThreshold` (default 0.45). Esto garantiza que el sustituto es netamente más seguro que el original.
3. Excluir candidatos cuyo `FoodId` pertenezca al `HashSet<Guid>` de alergias del paciente (redundante con el filtro previo pero defensivo).
4. Si el conjunto resultante es no vacío: elegir el candidato con menor `SymptomProbability` y reclasificar el item original como `ActionType.Substitute` con `SubstituteFoodId = candidato.FoodId`.
5. Si el conjunto resultante es vacío: el item queda como `Avoid` sin sustituto (`SubstituteFoodId = null`).

**Consecuencias**:
- La propuesta de sustitutos es determinística y reproducible bajo el mismo conjunto de candidatos.
- El allergy guardrail (DEC-B4-09) se respeta por construcción tanto sobre el item principal como sobre el sustituto.
- La restricción de misma categoría preserva la diversidad nutricional dentro del grupo alimentario (no se propone un cereal como sustituto de una fruta), alineado con el principio nutricional de equivalencia funcional.
- La degradación a `Avoid` puro cuando no hay sustituto válido es preferible a inventar uno arbitrario o relajar criterios, manteniendo la integridad clínica.

**Alternativas consideradas y descartadas**:
- *Sustituto cross-categoría con criterios nutricionales relajados*: descartada por riesgo de proponer sustituciones nutricionalmente no equivalentes (proteínas por carbohidratos, etc.) sin tener un modelo nutricional formal.
- *Sustituto buscado en todo el catálogo `food_items` (no solo en candidatos del historial del paciente)*: descartada porque introduciría alimentos que el paciente nunca ha consumido, contra el principio de DEC-B4-03 (recomendar sobre la dieta real).
- *Sin propuesta de sustituto en este Prompt, diferir Substitute a futuro*: descartada porque dejaría el enum `ActionType.Substitute` definido pero nunca emitido, induciendo confusión y dead code.

**Tests obligatorios**:
- `Handle_AvoidItem_WithValidSubstituteCandidate_PromotesToSubstitute`.
- `Handle_AvoidItem_WithNoSubstituteInSameCategory_RemainsAvoid`.
- `Handle_AvoidItem_WithSubstituteCandidateThatIsAllergen_RemainsAvoid`.
- `Handle_AvoidItem_PicksLowestScoreAmongValidSubstitutes`.

---

## DEC-B4-14 — Filtro de alergias por heurística (hasta catálogo formal `allergy_food_items`)

**Contexto**: el prompt original asume `PatientAllergy.FoodId`, pero el esquema real liga `PatientAllergy → AllergyId` (catálogo `allergies`: Gluten, Lactosa, Frutos secos, Mariscos, Huevo, Soya, Pescado, Sulfitos, Leguminosas, Fructosa) y `FoodItem` no posee tags de alérgenos. No existe tabla que mapee alergia↔alimento. DEC-B4-09 no es implementable como FK directa.

**Decisión**: la detección de alérgenos se realiza por heurística **estrictamente conservadora** (ante duda, EXCLUIR el alimento; preferir falso positivo a falso negativo, porque dejar pasar un alérgeno es clínicamente peor que excluir uno seguro). La lógica se aísla en `AllergyHeuristicMatcher` (separado de `PatientAllergyReader`):

- `Dictionary<string, AllergyMatchRule>` con una entrada por cada alergia del catálogo. Cada `AllergyMatchRule` contiene: substrings a buscar en `FoodItem.Name` (case-insensitive, sin acentos), valores exactos contra `FoodItem.Category`, substrings en `FoodItem.FodmapTags`.
- Si **cualquiera** de los tres campos matchea **cualquiera** de los patrones de la regla, el alimento se excluye.
- Si una alergia del catálogo no tiene regla con señal clara (p. ej. Sulfitos), su regla existe pero puede quedar mínima/vacía (no rompe el reader) y se registra un `warning` al construir el matcher.

`PatientAllergyReader` queda fino: consulta `PatientAllergy` join `Allergy` para obtener los nombres de alergias del paciente y delega a `AllergyHeuristicMatcher.GetForbiddenFoodIds(allergyNames, foodCatalog)`. Esto permite reemplazar el matcher por uno basado en la futura tabla `allergy_food_items` sin tocar reader ni handlers.

**Consecuencias**: el guardrail queda funcional con el esquema actual, aproximado y conservador. La intención de DEC-B4-09 se mantiene: ningún alimento marcado como alérgeno por el matcher aparece como `FoodId` ni `SubstituteFoodId`. La construcción del catálogo formal `allergy_food_items` con el nutricionista del Kaelín es **tarea pre-piloto** (ver `CLAUDE.md` → "Deuda técnica conocida").

**Tests obligatorios**: `PatientAllergyReader_LactoseAllergy_ExcludesMilkBasedFoods`, `PatientAllergyReader_GlutenAllergy_ExcludesWheatBasedFoods`, un test parametrizado con ≥1 caso positivo y ≥1 negativo por cada alergia del catálogo, y el crítico `Handler_PatientWithLactoseAllergy_RecommendationContainsNoDairyFoods`.

---

## Aclaración técnica — `AggregateConfidence` (fórmula explícita)

`AggregateConfidence` = promedio aritmético de `SymptomProbability` de los items cuya `ActionType ∈ {Avoid, Reduce}`. Items `Suggest`/`Substitute` se excluyen. Si no hay items accionables → `ConfidenceScore.Create(0m)`. Siempre pasa por `ConfidenceScore.Create(...)` para mantener la invariante [0,1] y el redondeo a 3 decimales. Se calcula en `FodmapRuleRecommendationEngine.ScoreFoodsAsync`, tras clasificar cada score por umbral (accionable ⇔ `score >= ReduceThreshold`). Justificación: la confianza debe medirse sobre las recomendaciones que mueven el comportamiento del paciente; promediar `Suggest` (de baja probabilidad por definición) diluiría el score y bloquearía el `AutoApprovalGuard` aunque las recomendaciones críticas fueran de alta confianza.

---

## Actas de cambio (desvíos prompt → código real)

El plan del módulo se aprobó con el criterio "el código existente gana sobre el prompt". Cada desvío se registra aquí.

| # | Prompt | Implementado |
|---|---|---|
| A1 | `ICommand<T>`/`IQuery<T>` | `IRequest<TResponse>` (MediatR) + marcador `IIdempotentCommand` |
| A2 | Comandos con `PatientId`/`NutritionistId`/`IdempotencyKey` | Identidad resuelta en el handler vía `ICurrentUserService` → `IUserRepository.FindByKeycloakIdAsync` → check de rol; idempotencia vía `IIdempotentCommand.ClientGuid` (header `Idempotency-Key`) |
| A3 | `Commands/` + `Queries/` | `Recommendations/UseCases/<Nombre>/` |
| A4 | `Recommendations/Abstractions/` | Interfaces en `Common/Interfaces/Recommendations/`; DTOs en `Recommendations/Dtos/`; contratos motor/LLM en `Recommendations/Contracts/` |
| A5 | Todo infra bajo `Infrastructure/Recommendations/` | EF configs/migración/repos/seeder en `Persistence/*`; engines/LLM/readers en `Infrastructure/Recommendations/*` |
| A6 | `AddRecommendationsModule(...)` desde `Program.cs` | Registro dentro de `AddInfrastructure`; handlers/validators/mappings por escaneo de ensamblado en `AddApplication` |
| A7 | Seeder en bloque propio de `Program.cs` | Invocación dentro de `RunDevelopmentSeedAsync` |
| A8 | DEC-B4-12 resource-based policies | Validación de ownership/asignación en el handler (ver DEC-B4-12) |
| A9 | Entidades `: AggregateRoot` con `RecommendationId`/`VersionId` | `: Entity, IAggregateRoot` con `Id` base mapeado a `recommendation_id`/`version_id` |
| A10 | Enums `HasConversion<string>()` con miembros `Pending_Review`/`Llm_Generated`/`No_Change` | `SnakeCaseEnumConverter<T>` (DB snake_case) con miembros PascalCase sin guión bajo (`PendingReview`, `LlmGenerated`, `NoChange`); el converter inserta `_` antes de cada mayúscula |
| A11 | Eventos en outbox "ya establecido" | No existe outbox ni dispatcher; los 6 records de evento se definen (forward-compat Prompt 5) pero **no** se emiten ni despachan |
| A12 | Fallos con `Result.Failure(...)` | Excepciones de dominio mapeadas por `ExceptionHandlingMiddleware`: 422 (`insufficient_clinical_history`/`all_candidates_filtered_by_allergies`/`no_active_model_version`), 409 `conflict_state`, 404 `recommendation_not_found`, 403 `recommendation_access_denied` |
| A13 | `Cauce.Integration.Tests` | `tests/Cauce.Api.IntegrationTests/Recommendations/` |
| A14 | `DECISIONS-BLOCK-02/03.md` como lectura | No existen; fuente de verdad = código de Identity/Patients/ClinicalRegistry |
| A15 | `idempotency_conflict` | `IdempotencyMismatchException` → 409 `idempotency_mismatch` (ya existente) |
| A16 | `IExplanationOrchestrator.ExplainAsync(..., IReadOnlyList<RecommendationItem>)` | El orquestador y `RecommendationPromptTemplate` operan sobre `ExplanationItem` (FoodName + ActionType + Reasoning), construido por el handler con los nombres de los candidatos; `RecommendationItem` no porta `FoodName` |
