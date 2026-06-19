workspace "Sistema de Recomendaciones Dietéticas para SII" "Arquitectura del sistema mHealth para pacientes con Síndrome del Intestino Irritable" {

    model {

        // ── ACTORES HUMANOS ──────────────────────────────────────────
        paciente = person "Paciente con SII" "Registra comidas y síntomas. Recibe recomendaciones dietéticas personalizadas."

        nutricionista = person "Dietista-Nutricionista" "Valida recomendaciones y monitorea la evolución clínica de sus pacientes."

        // ── SISTEMAS EXTERNOS ────────────────────────────────────────
        keycloak = softwareSystem "Keycloak" "Servidor de identidad. Emite y valida tokens JWT mediante OIDC." "Sistema Externo"

        fcm = softwareSystem "Firebase Cloud Messaging" "Notificaciones push a dispositivos móviles." "Sistema Externo"

        smtp = softwareSystem "Servicio SMTP" "Envío de correos electrónicos transaccionales." "Sistema Externo"

        llmApi = softwareSystem "API de IA Generativa" "Genera explicaciones en lenguaje natural para las recomendaciones." "Sistema Externo"

        // ── SISTEMA PRINCIPAL ────────────────────────────────────────
        sistema = softwareSystem "Sistema de Recomendaciones Dietéticas SII" {

            appMovil = container "Aplicación Móvil" "Cliente Flutter para pacientes. Soporte offline con sincronización diferida." "Flutter / Dart" "Mobile App"

            sqliteLocal = container "Base de Datos Local" "Almacenamiento local en el dispositivo del paciente." "SQLite" "Database"

            portalWeb = container "Portal Web" "SPA para gestión clínica y validación de recomendaciones." "React / TypeScript" "Web App"

            backend = container "Backend Monolito Modular" "API REST con lógica de negocio e inferencia ONNX integrada." "ASP.NET Core / C#" "Backend" {

                // ─── CAPA DE ENTRADA (FACHADA) ───────────────────────
                apiGateway = component "API Gateway" "Punto único de entrada REST. Enruta peticiones y aplica autenticación." "ASP.NET Core Controllers" "Application"

                // ─── MÓDULOS DE DOMINIO ──────────────────────────────
                moduloIdentidad = component "Módulo de Identidad" "Valida tokens JWT y aplica autorización por rol." "ASP.NET Core" "Domain"

                moduloRegistro = component "Módulo de Registro Clínico" "Gestiona comidas, síntomas y notas. Idempotencia para sync offline." "ASP.NET Core" "Domain"

                moduloPacientes = component "Módulo de Pacientes" "Perfil clínico, IBS-SSS, códigos de invitación y asignaciones." "ASP.NET Core" "Domain"

                motorRecomendaciones = component "Motor de Recomendaciones" "Inferencia ML con ONNX Runtime. Decide aprobación automática o HITL." "ASP.NET Core + ONNX Runtime" "Domain"

                orquestadorLLM = component "Orquestador LLM" "Prompts con guardrails clínicos e invocación de la API generativa." "ASP.NET Core" "Domain"

                servicioHITL = component "Servicio HITL" "Máquina de estados de recomendaciones y revisión clínica." "ASP.NET Core" "Domain"

                generadorPDF = component "Generador de Reportes PDF" "Produce PDFs clínicos protegidos con contraseña." "ASP.NET Core" "Domain"

                // ─── WORKERS ASÍNCRONOS ──────────────────────────────
                workerSync = component "Worker de Sincronización" "Consume lotes de la cola y procesa registros offline de la app móvil." "IHostedService" "Worker"

                workerNotif = component "Worker de Notificaciones" "Consume eventos de la cola y despacha push y correos." "IHostedService" "Worker"

                // ─── INFRAESTRUCTURA TRANSVERSAL ─────────────────────
                auditMiddleware = component "Audit Middleware" "Registra eventos de aplicación: login, decisiones HITL, exportaciones." "ASP.NET Core Middleware" "Infrastructure"

                auditTriggers = component "Audit Triggers" "Registra cambios sobre tablas críticas a nivel de base de datos." "PostgreSQL Triggers" "Infrastructure"
            }

            postgres = container "Base de Datos Principal" "Perfiles, registros, recomendaciones y audit logs." "PostgreSQL" "Database"

            keydb = container "Caché y Cola de Eventos" "Caché en memoria y cola asíncrona para notificaciones y sincronización." "KeyDB" "Cache"

            minio = container "Almacenamiento de Objetos" "Reportes PDF y artefactos del modelo ONNX." "MinIO" "Storage"
        }

        // ── RELACIONES DE ACTORES ────────────────────────────────────
        paciente -> appMovil "Usa"
        nutricionista -> portalWeb "Gestiona y valida"

        // ── RELACIONES DE CONTENEDORES ───────────────────────────────
        appMovil -> sqliteLocal "Lee y escribe offline"
        appMovil -> backend "HTTPS / REST"
        portalWeb -> backend "HTTPS / REST"

        backend -> postgres "TCP / SQL"
        backend -> keydb "Caché y eventos"
        backend -> minio "Objetos binarios"
        backend -> keycloak "Validación JWT"
        backend -> fcm "Notificaciones push"
        backend -> smtp "Correos transaccionales"
        backend -> llmApi "Generación de explicaciones"

        // ── RELACIONES DE COMPONENTES ────────────────────────────────
        // Los clientes solo conocen el API Gateway
        appMovil -> apiGateway "Realiza peticiones REST" "HTTPS / JSON"
        portalWeb -> apiGateway "Realiza peticiones REST" "HTTPS / JSON"

        // El Gateway delega a los módulos de dominio
        apiGateway -> moduloIdentidad "Valida autenticación"
        apiGateway -> moduloRegistro "Delega operaciones de registro clínico"
        apiGateway -> moduloPacientes "Delega gestión de pacientes"
        apiGateway -> servicioHITL "Delega operaciones de recomendaciones"
        apiGateway -> generadorPDF "Solicita generación de reportes"

        // Sincronización offline desacoplada vía cola
        apiGateway -> keydb "Publica lote de sincronización offline"
        workerSync -> keydb "Consume lotes de sincronización"
        workerSync -> moduloRegistro "Procesa cada registro del lote"

        // Validación de identidad
        moduloIdentidad -> keycloak "Valida JWT mediante OIDC"

        // Persistencia: cada módulo escribe en sus propias tablas
        moduloRegistro -> postgres "Persiste comidas, síntomas y notas" "" "Persistence"
        moduloPacientes -> postgres "Persiste perfiles e IBS-SSS" "" "Persistence"
        servicioHITL -> postgres "Persiste recomendaciones" "" "Persistence"
        generadorPDF -> postgres "Consulta historial clínico" "" "Persistence"

        // Flujo de IA
        servicioHITL -> motorRecomendaciones "Solicita generación de recomendación"
        motorRecomendaciones -> postgres "Lee historial del paciente" "" "Persistence"
        motorRecomendaciones -> orquestadorLLM "Solicita explicación tras inferencia"
        orquestadorLLM -> llmApi "Invoca con guardrails"

        // Cola de eventos asíncronos (notificaciones)
        servicioHITL -> keydb "Publica evento de notificación"
        workerNotif -> keydb "Consume eventos"
        workerNotif -> fcm "Envía push"
        workerNotif -> smtp "Envía correo"

        // Almacenamiento de objetos
        generadorPDF -> minio "Almacena PDF generado"

        // Auditoría: middleware en aplicación + triggers en BD
        auditMiddleware -> postgres "Registra eventos de aplicación" "" "Audit"
        auditTriggers -> postgres "Registra cambios sobre tablas críticas" "" "Audit"
        moduloRegistro -> auditMiddleware "Notifica operaciones críticas"
        servicioHITL -> auditMiddleware "Notifica decisiones HITL"
        moduloPacientes -> auditMiddleware "Notifica cambios sensibles"
        generadorPDF -> auditMiddleware "Notifica generación de reporte"

        // ── ENTORNO DE DESPLIEGUE: PILOTO ─────────────────────────────
        deploymentEnvironment "Piloto Clínico" {

            deploymentNode "Dispositivo Móvil del Paciente" "Android 8+ / iOS 13+" "Smartphone" {
                deploymentNode "Aplicación Flutter Nativa" "APK / IPA compilado" "Runtime Móvil" {
                    containerInstance appMovil
                    containerInstance sqliteLocal
                }
            }

            deploymentNode "Navegador del Nutricionista" "Chrome / Edge / Firefox" "Browser" {
                containerInstance portalWeb
            }

            deploymentNode "Servidor del Piloto" "Ubuntu Server 22.04 LTS" "Servidor Linux" {

                deploymentNode "NGINX + ModSecurity" "Reverse Proxy y WAF" "Docker Container" {
                    description "Punto de entrada único. Termina TLS y aplica reglas WAF."
                }

                deploymentNode "Contenedor Backend" "Docker Container" "Runtime .NET" {
                    containerInstance backend
                }

                deploymentNode "Contenedor PostgreSQL" "Docker + Volumen Persistente" "Runtime DB" {
                    containerInstance postgres
                }

                deploymentNode "Contenedor KeyDB" "Docker + Persistencia AOF" "Runtime Cache" {
                    containerInstance keydb
                }

                deploymentNode "Contenedor MinIO" "Docker + Volumen Persistente" "Runtime Storage" {
                    containerInstance minio
                }

                deploymentNode "Contenedor Keycloak" "Docker Container" "Runtime IdP" {
                    softwareSystemInstance keycloak
                }

                deploymentNode "Stack de Observabilidad" "Docker Compose" "Monitoreo" {
                    description "Prometheus para métricas, Grafana para dashboards, Loki para logs centralizados."
                }
            }

            deploymentNode "Servicios Externos en la Nube" "Internet" "Cloud" {
                softwareSystemInstance fcm
                softwareSystemInstance smtp
                softwareSystemInstance llmApi
            }
        }
    }

    views {

        systemContext sistema "Contexto" {
            include *
            autoLayout lr
            description "Actores humanos y sistemas externos del sistema."
        }

        container sistema "Contenedores" {
            include *
            autoLayout lr
            description "Contenedores del sistema y sus tecnologías."
        }

        // ─── VISTA GENERAL DE COMPONENTES ────────────────────────────
        component backend "ComponentesGeneral" {
            include *
            autoLayout lr
            description "Vista general de todos los componentes del backend."
        }

        // ─── VISTA FILTRADA: AUTENTICACIÓN ───────────────────────────
        component backend "ComponentesAutenticacion" {
            include apiGateway moduloIdentidad keycloak appMovil portalWeb
            autoLayout lr
            description "Flujo de autenticación: clientes, gateway, módulo de identidad y Keycloak."
        }

        // ─── VISTA FILTRADA: REGISTRO CLÍNICO ────────────────────────
        component backend "ComponentesRegistro" {
            include apiGateway moduloRegistro workerSync keydb postgres auditMiddleware appMovil
            autoLayout lr
            description "Registro clínico diario: ingesta, sincronización offline desacoplada y persistencia."
        }

        // ─── VISTA FILTRADA: RECOMENDACIONES E IA ────────────────────
        component backend "ComponentesIA" {
            include apiGateway servicioHITL motorRecomendaciones orquestadorLLM llmApi postgres auditMiddleware portalWeb
            autoLayout lr
            description "Motor de IA: generación, explicación XAI y flujo HITL."
        }

        // ─── VISTA FILTRADA: REPORTES Y NOTIFICACIONES ───────────────
        component backend "ComponentesReportes" {
            include apiGateway generadorPDF workerNotif keydb minio fcm smtp postgres
            autoLayout lr
            description "Generación de reportes PDF y entrega de notificaciones asíncronas."
        }

        // ─── VISTA DE DESPLIEGUE ─────────────────────────────────────
        deployment sistema "Piloto Clínico" "Despliegue" {
            include *
            autoLayout tb
            description "Despliegue del sistema en el entorno del piloto clínico."
        }

        styles {

            element "Person" {
                color #ffffff
                background #08427b
                shape Person
                fontSize 28
            }

            element "Sistema Externo" {
                background #555555
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Software System" {
                background #1a5276
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Mobile App" {
                background #1a6fa8
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Web App" {
                background #1a6fa8
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Backend" {
                background #1a6fa8
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Database" {
                background #1a6fa8
                color #ffffff
                shape Cylinder
                fontSize 28
            }

            element "Cache" {
                background #1a6fa8
                color #ffffff
                shape Cylinder
                fontSize 28
            }

            element "Storage" {
                background #1a6fa8
                color #ffffff
                shape Cylinder
                fontSize 28
            }

            element "Application" {
                background #2874a6
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Domain" {
                background #1a6fa8
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Worker" {
                background #5b8def
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Infrastructure" {
                background #6c7a89
                color #ffffff
                shape Component
                fontSize 28
            }

            // Nodos de despliegue
            element "Smartphone" {
                background #2c3e50
                color #ffffff
                shape MobileDevicePortrait
                fontSize 28
            }

            element "Browser" {
                background #2c3e50
                color #ffffff
                shape WebBrowser
                fontSize 28
            }

            element "Servidor Linux" {
                background #2c3e50
                color #ffffff
                shape RoundedBox
                fontSize 19
            }

            element "Docker Container" {
                background #1a6fa8
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            element "Cloud" {
                background #555555
                color #ffffff
                shape RoundedBox
                fontSize 28
            }

            relationship "Relationship" {
                thickness 2
                fontSize 25
                color #cccccc
            }

            relationship "Persistence" {
                color #2ecc71
                dashed true
            }

            relationship "Audit" {
                color #e67e22
                dashed true
            }
        }
    }
}