# Matriz de Criterios de Aceptación — Bloque 4 (Recommendations)

Trazabilidad entre los criterios de aceptación del módulo de recomendaciones y las pruebas que
los verifican. Los nombres de prueba corresponden a las clases de
`Cauce.Domain.Tests`, `Cauce.Application.Tests`, `Cauce.Infrastructure.Tests` y
`Cauce.Api.IntegrationTests` bajo la carpeta `Recommendations`.

| Código | Criterio | Verificado por |
| --- | --- | --- |
| CA-B4-01 | Genera una recomendación cuando el paciente lo solicita y tiene historial suficiente. | `GenerateRecommendationCommandHandlerTests.Handle_HappyPath_PersistsPendingReview`; `RecommendationsApiTests.FullFlow_Generate_Approve_Deliver_Feedback` |
| CA-B4-02 | Rechaza con 422 si el paciente tiene menos del mínimo de alimentos en 14 y 30 días. | `Handle_WithInsufficientHistory_Throws`; `RecommendationsApiTests.Generate_WithInsufficientHistory_Returns422` |
| CA-B4-03 | Filtra las alergias del paciente antes de pasar candidatos al motor. | `Handle_AllergyFilter_NeverIncludesAllergenInItems` |
| CA-B4-04 | Los sustitutos propuestos nunca son alérgenos del paciente. | `Handle_AllergyFilter_NeverIncludesAllergenInItems` (verifica `FoodId` y `SubstituteFoodId`) |
| CA-B4-05 | Con auto-aprobación deshabilitada, toda recomendación va a `PendingReview`. | `Handle_HappyPath_PersistsPendingReview` |
| CA-B4-06 | Con auto-aprobación habilitada y criterios cumplidos, queda `Approved` sin intervención. | `Handle_WithAutoApprovalEnabled_AndCriteriaMet_AutoApproves` |
| CA-B4-07 | El motor por regla calcula puntajes en [0, 1]. | `FodmapRuleRecommendationEngineTests.ScoreFoodsAsync_ProducesScoresWithinRange` |
| CA-B4-08 | La explicación se persiste con `LlmGenerated` cuando Ollama responde válidamente. | `RecommendationsApiTests.FullFlow_...` (asserta `explanationSource == "LlmGenerated"`) |
| CA-B4-09 | La explicación cae a `Fallback` cuando Ollama falla, hace timeout o no pasa guardrails. | `RecommendationsApiTests.Generate_WithOllamaDown_FallsBackSuccessfully`; `Generate_WithOllamaUnsafeOutput_FallsBack`; `Handle_WhenExplanationReturnsFallback_PersistsWithFallbackSource` |
| CA-B4-10 | Los guardrails rechazan output con frases clínicas prohibidas. | `RecommendationGuardrailsValidatorTests.Validate_ContainsClinicalTerm_Fails` |
| CA-B4-11 | Los guardrails rechazan output que no esté en español. | `RecommendationGuardrailsValidatorTests.Validate_NonSpanishText_Fails` |
| CA-B4-12 | El nutricionista aprueba con nota clínica obligatoria de mínimo 10 caracteres. | `RecommendationValidatorsTests.ApproveValidator_ShortNote_Fails` / `ApproveValidator_ValidNote_Succeeds` |
| CA-B4-13 | El nutricionista rechaza con motivo obligatorio. | `RecommendationValidatorsTests.RejectValidator_EmptyReason_Fails` |
| CA-B4-14 | El nutricionista solo aprueba/rechaza recomendaciones de pacientes asignados. | `ApproveRecommendationCommandHandlerTests.Handle_NutritionistNotAssigned_Throws`; `RecommendationsApiTests.Approve_NutritionistNotAssigned_Returns403` |
| CA-B4-15 | El paciente solo ve/entrega/da feedback sobre sus propias recomendaciones. | `DeliverRecommendationCommandHandlerTests.Handle_NotOwner_Throws`; `GetRecommendationByIdQueryHandlerTests.Handle_PatientNotOwner_Throws`; `RecommendationsApiTests.GetById_OtherPatient_Returns403` |
| CA-B4-16 | La transición a `Expired` ocurre on-read cuando `expires_at < now`. | `GetRecommendationByIdQueryHandlerTests.Handle_WhenExpiresAtPast_AndStatusEligible_TransitsToExpired` |
| CA-B4-17 | Las recomendaciones expiradas no se entregan al paciente. | `DeliverRecommendationCommandHandlerTests.Handle_Expired_ExpiresAndThrows` |
| CA-B4-18 | El feedback solo se acepta sobre recomendaciones en estado `Delivered`. | `SubmitFeedbackCommandHandlerTests.Handle_FromNonDeliveredState_Throws` |
| CA-B4-19 | Cada recomendación tiene a lo sumo un feedback (unique + máquina de estados). | `RecommendationFeedbackConfiguration` (índice único) + `RecommendationTests.RecordFeedback_FromApproved_Throws` |
| CA-B4-20 | `model_versions` permite una sola versión activa (constraint a nivel BD). | Migración `AddRecommendationsModule` (`ix_model_versions_only_one_active`); `RecommendationsApiTests.Seeder_InsertsRuleVersionAsActive` |
| CA-B4-21 | El seeder inserta `rule-v1.0.0` como activa, idempotentemente. | `RecommendationsApiTests.Seeder_InsertsRuleVersionAsActive` / `Seeder_IsIdempotent_DoesNotInsertTwice` |
| CA-B4-22 | La migración agrega 4 columnas FODMAP granulares con CHECK. | `RecommendationsApiTests.Migration_AddsFodmapGranularColumnsToFoodItems` / `Migration_RespectsCheckConstraints_RejectsValueAbove2` |
| CA-B4-23 | Los endpoints POST respetan el replay idempotente. | `RecommendationsApiTests.Generate_IdempotentReplay_ReturnsCachedResult` |
| CA-B4-24 | Un payload distinto con misma `Idempotency-Key` retorna 409. | `RecommendationsApiTests.SubmitFeedback_SameKeyDifferentPayload_Returns409` |
| CA-B4-25 | La eliminación de un paciente hace cascade de sus recomendaciones. | Migración `AddRecommendationsModule` (FK `patient_id` ON DELETE CASCADE) |
| CA-B4-26 | La eliminación de un `ModelVersion` con recomendaciones está bloqueada. | Migración `AddRecommendationsModule` (FK `model_version_id` ON DELETE RESTRICT) |
| CA-B4-27 | El conjunto de candidatos se expande a 30 días si en 14 no hay suficiente. | `GenerateRecommendationCommandHandlerTests.Handle_ExpandsCandidateWindow_WhenInsufficientInInitialWindow` |
| CA-B4-28 | Sin versión activa de modelo, el sistema retorna 422 `no_active_model_version`. | `GenerateRecommendationCommandHandlerTests.Handle_WhenNoActiveModelVersion_Throws` |
| CA-B4-29 | Los ítems `Avoid` se promueven a `Substitute` cuando existe candidato en la misma categoría con score < `ReduceThreshold` y no alérgeno; si no, permanecen `Avoid`. | `Handle_AvoidItem_WithValidSubstituteCandidate_PromotesToSubstitute`; `Handle_AvoidItem_WithNoSubstituteInSameCategory_RemainsAvoid` |

## Confianza agregada (aclaración técnica del Bloque 4)

| Prueba | Verifica |
| --- | --- |
| `FodmapRuleRecommendationEngineTests.AggregateConfidence_WithOnlySuggestItems_IsZero` | Confianza 0 sin ítems accionables |
| `FodmapRuleRecommendationEngineTests.AggregateConfidence_WithOnlyAvoidItems_AveragesAllOfThem` | Promedio de ítems accionables |
| `FodmapRuleRecommendationEngineTests.AggregateConfidence_WithMixedActions_AveragesOnlyAvoidAndReduce` | Excluye `Suggest`/`Substitute` del promedio |

## Prompt LLM (aclaración técnica del Bloque 4)

| Prueba | Verifica |
| --- | --- |
| `RecommendationPromptTemplateTests.Build_RendersActionTypeInSpanish` | Acción en español (evitar/reducir/…) |
| `RecommendationPromptTemplateTests.Build_OmitsReasoningWhenNullOrEmpty` | Omite el razonamiento vacío |
| `RecommendationPromptTemplateTests.Build_TruncatesReasoningAtOneHundredTwenty` | Trunca a 117 + "…" |

## Filtro de alergias heurístico (DEC-B4-14)

| Prueba | Verifica |
| --- | --- |
| `AllergyHeuristicMatcherTests.LactoseAllergy_ExcludesMilkBasedFoods` | Exclusión por lácteos |
| `AllergyHeuristicMatcherTests.GlutenAllergy_ExcludesWheatBasedFoods` | Exclusión por trigo |
| `AllergyHeuristicMatcherTests.KnownAllergy_ExcludesMatchingFood` (parametrizado) | ≥1 positivo por alergia del catálogo |
| `AllergyHeuristicMatcherTests.KnownAllergy_DoesNotExcludeUnrelatedFood` (parametrizado) | ≥1 negativo por alergia del catálogo |
| `AllergyHeuristicMatcherTests.UnknownAllergy_ExcludesNothing` | Alergia sin regla no excluye nada |

---

# Matriz de Criterios de Aceptación — Bloque 7b (features clínicas independientes pre-OE3)

Trazabilidad de las nueve historias cerradas en el Bloque 7b. Decisiones vinculantes en
`docs/decisions/DECISIONS-BLOCK-07B.md` (DEC-B7B-01..09, actas A25–A29).

| Historia / CA | Criterio | Endpoint / Handler | Verificado por |
| --- | --- | --- | --- |
| US18 | Panel de triaje prioriza pacientes por urgencia (severidad, revisiones vencidas, actividad). | `GET /api/v1/nutritionists/me/patients` · `ListAssignedPatientsQueryHandler` | `ListAssignedPatientsQueryHandlerTests.Handle_MixedPatients_OrdersByPriorityThenScore` / `Handle_ProlongedInactivity_MarksMediumPriority`; `NutritionistPatientInsightsApiTests.Triage_OrdersSeverePatientFirst` |
| US21 | El nutricionista ve la evolución de un paciente asignado; 403 si no lo tiene asignado. | `GET /api/v1/nutritionists/me/patients/{id}/evolution` · `GetPatientEvolutionForNutritionistQueryHandler` | `GetPatientEvolutionForNutritionistQueryHandlerTests.Handle_AssignedWithSignificantImprovement_ReturnsMetrics` / `Handle_NotAssigned_ThrowsForbidden`; `NutritionistPatientInsightsApiTests.Evolution_AssignedPatient_ReturnsMetrics` / `Evolution_NotAssignedPatient_Returns403` |
| US24 | El paciente genera su propio reporte PDF cifrado; URL y contraseña por correos separados; 422 sin datos. | `POST /api/v1/patients/me/report` · `GenerateMyClinicalReportCommandHandler` | `MyClinicalReportApiTests.GenerateMyReport_HappyPath_ReturnsEncryptedPdfWithTwoEmailsAndAudit` / `GenerateMyReport_NoData_Returns422` |
| US09 CA03 | Sugerencias de alimentos: frecuentes (30 d), recientes (24 h) y catálogo determinista. | `GET /api/v1/foods/suggestions` · `GetFoodSuggestionsQueryHandler` | `PatientSelfInsightsApiTests.FoodSuggestions_ReturnsFrequentRecentAndCatalogLists` |
| US10 CA03 | Advertencia de alérgenos al crear comida personalizada: 409 con detalle si no se confirma; acuse si se confirma. | `POST /api/v1/custom-foods` · `CreateCustomFoodCommandHandler` + `ICustomFoodAllergenChecker` | `CustomFoodAllergenApiTests.Create_WithAllergenIngredientUnconfirmed_Returns409WithDetail` / `Create_WithAllergenIngredientConfirmed_CreatesAndAudits` / `Create_WithoutAllergies_CreatesNormally` |
| US28 | Perfil agregado del paciente: identificación (correo enmascarado), clínico, evolución y nutricionista. | `GET /api/v1/patients/me/summary` · `GetMyProfileSummaryQueryHandler` | `PatientSelfInsightsApiTests.MyProfileSummary_ReturnsAggregatedMetricsAndMaskedEmail` |
| US27 | Glosario clínico: listado, búsqueda insensible a tildes, definición por rol, contenido en borrador. | `GET /api/v1/glossary` · `GET /api/v1/glossary/search` · `GetGlossaryQueryHandler` / `SearchGlossaryQueryHandler` | `GlossaryApiTests.List_AsPatient_ReturnsPatientDefinitionsOrderedWithDraftStatus` / `List_AsNutritionist_ReturnsTechnicalDefinition` / `Search_WithoutAccent_MatchesAccentedTermViaUnaccent` |
| US12 CA02 | Recordatorio IBS-SSS a las 48 h de vencida y marca como perdida a los 7 días; se agenda la siguiente al registrar. | `IbsSssScheduleProcessor` + `IbsSssReminderWorker`; agenda en `CreateIbsSssAssessmentCommandHandler` | `CreateIbsSssAssessmentCommandHandlerTests.Handle_Baseline_SchedulesNextAssessment` / `Handle_Periodic_ClosesOpenScheduleAndCreatesNext`; `IbsSssScheduleApiTests.SubmitBaseline_CreatesNextSchedule` / `Processor_ScheduleOverdue48Hours_SendsReminderOnce` / `Processor_ScheduleOverdue7Days_MarksMissed` |
| TS11 / US22 CA01 | Gráfico de evolución IBS-SSS embebido en el PDF (ScottPlot). | `IbsSssChartRenderer` + `ClinicalReportDocument` | `MyClinicalReportApiTests.GenerateMyReport_HappyPath_...` (PDF descargable con el gráfico); `ReportsApiTests.Generate_HappyPath_ProducesDownloadableEncryptedPdf` |
