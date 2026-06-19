workspace "Sistema de Recomendaciones Dietéticas para SII" "Arquitectura del sistema mHealth para pacientes con Síndrome del Intestino Irritable" {

    model {

        // ── ACTORES HUMANOS ──────────────────────────────────────────
        paciente = person "Paciente con SII" "Registra comidas y síntomas. Recibe recomendaciones dietéticas personalizadas."

        nutricionista = person "Dietista-Nutricionista" "Valida recomendaciones y monitorea la evolución clínica de sus pacientes."

        // ── SISTEMAS EXTERNOS ────────────────────────────────────────
        keycloak = softwareSystem "Keycloak" "Servidor de identidad. Emite y valida JWT, y expone Admin API." "Sistema Externo"

        fcm = softwareSystem "Firebase Cloud Messaging" "Notificaciones push a dispositivos móviles." "Sistema Externo"

        smtp = softwareSystem "Servicio SMTP" "Envío de correos electrónicos transaccionales." "Sistema Externo"

        // ── SISTEMA PRINCIPAL ────────────────────────────────────────
        sistema = softwareSystem "Sistema de Recomendaciones Dietéticas SII" {

            appMovil = container "Aplicación Móvil" "Cliente Flutter para pacientes con soporte offline." "Flutter / Dart" "Mobile App"

            sqliteLocal = container "Base de Datos Local" "Almacenamiento local en el dispositivo del paciente." "SQLite" "Database"

            portalWeb = container "Portal Web" "SPA para gestión clínica y validación HITL." "React / TypeScript" "Web App"

            backend = container "Backend Monolito Modular" "API REST con lógica de negocio e inferencia ONNX integrada." "ASP.NET Core / C#" "Backend" {

                // ─── CAPA DE ENTRADA (FACHADA) ───────────────────────
                apiGateway = component "API Gateway" "Punto único de entrada REST. Enruta peticiones y aplica autenticación." "ASP.NET Core Controllers" "Application"

                // ─── MÓDULOS DE DOMINIO ──────────────────────────────
                moduloIdentidad = component "Módulo de Identidad" "Valida JWT, autoriza por rol y gestiona consentimientos." "ASP.NET Core" "Domain"

                moduloRegistro = component "Módulo de Registro Clínico" "Gestiona comidas, síntomas y notas. Idempotencia para sync offline." "ASP.NET Core" "Domain"

                moduloPacientes = component "Módulo de Pacientes" "Perfil clínico, alergias, IBS-SSS, códigos de invitación y asignaciones." "ASP.NET Core" "Domain"

                motorRecomendaciones = component "Motor de Recomendaciones" "Inferencia ML con ONNX Runtime. Encapsula predicción y explicación." "ASP.NET Core + ONNX Runtime" "Domain"

                orquestadorLLM = component "Orquestador LLM" "Construye prompts con guardrails. Invoca el servicio LLM local." "ASP.NET Core" "Domain"

                servicioHITL = component "Servicio HITL" "Máquina de estados, revisión clínica y recepción de feedback." "ASP.NET Core" "Domain"

                generadorPDF = component "Generador de Reportes PDF" "Produce PDFs clínicos protegidos con contraseña." "ASP.NET Core" "Domain"

                // ─── WORKERS ASÍNCRONOS ──────────────────────────────
                workerSync = component "Worker de Sincronización" "Consume lotes y procesa registros offline." "IHostedService" "Worker"

                workerNotif = component "Worker de Notificaciones" "Despacha push y correos. Actualiza estado tras cada intento." "IHostedService" "Worker"

                // ─── INFRAESTRUCTURA TRANSVERSAL ─────────────────────
                auditMiddleware = component "Audit Middleware" "Registra eventos de aplicación como login, HITL y exportaciones." "ASP.NET Core Middleware" "Infrastructure"

                auditTriggers = component "Audit Triggers" "Registra cambios sobre tablas críticas en la base de datos." "PostgreSQL Triggers" "Infrastructure"
            }

            postgres = container "Base de Datos Principal" "Perfiles, registros, recomendaciones, consentimientos y audit logs." "PostgreSQL" "Database"

            keydb = container "Caché y Cola de Eventos" "Caché en memoria y cola asíncrona para notificaciones y sync." "KeyDB" "Cache"

            minio = container "Almacenamiento de Objetos" "Reportes PDF y artefactos del modelo ONNX." "MinIO" "Storage"

            // ─── SERVICIO LLM LOCAL ──────────────────────────────────
            servicioLLM = container "Servicio LLM Local" "Genera explicaciones en lenguaje natural sin sacar datos del servidor." "Ollama / Llama 3.1 8B" "LLM Service"
        }

        // ── RELACIONES DE ACTORES ────────────────────────────────────
        paciente -> appMovil "Usa"
        nutricionista -> portalWeb "Gestiona y valida"

        // ── RELACIONES DE CONTENEDORES ───────────────────────────────
        appMovil -> sqliteLocal "Persiste registros local mientras está offline"
        appMovil -> backend "Sincroniza lotes cuando hay conectividad" "HTTPS / JSON batch"
        portalWeb -> backend "HTTPS / REST"

        backend -> postgres "TCP / SQL"
        backend -> keydb "Caché y eventos"
        backend -> minio "Objetos binarios"
        backend -> keycloak "Validación JWT y Admin API"
        backend -> fcm "Notificaciones push"
        backend -> smtp "Correos transaccionales"
        backend -> servicioLLM "Solicita generación de explicaciones"

        // ── RELACIONES DE COMPONENTES ────────────────────────────────
        appMovil -> apiGateway "Realiza peticiones REST y envía feedback" "HTTPS / JSON"
        portalWeb -> apiGateway "Realiza peticiones REST" "HTTPS / JSON"

        apiGateway -> moduloIdentidad "Valida autenticación y gestiona consentimientos"
        apiGateway -> moduloRegistro "Delega operaciones de registro clínico"
        apiGateway -> moduloPacientes "Delega gestión de pacientes"
        apiGateway -> servicioHITL "Delega operaciones y feedback de recomendaciones"
        apiGateway -> generadorPDF "Solicita generación de reportes"

        apiGateway -> keydb "Publica lote de sincronización offline"
        workerSync -> keydb "Consume lotes de sincronización"
        workerSync -> moduloRegistro "Procesa cada registro del lote"

        moduloIdentidad -> keycloak "Valida JWT y solicita cambios de contraseña vía Admin API"
        moduloIdentidad -> postgres "Persiste registros de consentimiento y tokens de reset"
        moduloIdentidad -> auditMiddleware "Notifica eventos de autenticación"

        moduloRegistro -> postgres "Persiste comidas, ítems, síntomas y notas clínicas"
        moduloPacientes -> postgres "Persiste perfiles, alergias, IBS-SSS y asignaciones"
        servicioHITL -> postgres "Persiste recomendaciones, ítems y feedback"
        generadorPDF -> postgres "Consulta historial clínico"

        servicioHITL -> motorRecomendaciones "Solicita generación de recomendación"
        motorRecomendaciones -> postgres "Lee historial del paciente y versión activa del modelo"
        motorRecomendaciones -> orquestadorLLM "Solicita explicación tras inferencia"
        orquestadorLLM -> servicioLLM "Invoca con prompts protegidos por guardrails clínicos"

        servicioHITL -> keydb "Publica evento de notificación"
        workerNotif -> keydb "Consume eventos"
        workerNotif -> fcm "Envía push"
        workerNotif -> smtp "Envía correo"
        workerNotif -> postgres "Actualiza estado de entrega y reintentos"

        generadorPDF -> minio "Almacena PDF generado"

        auditMiddleware -> postgres "Registra eventos de aplicación"
        auditTriggers -> postgres "Registra cambios sobre tablas críticas"
        moduloRegistro -> auditMiddleware "Notifica operaciones críticas"
        servicioHITL -> auditMiddleware "Notifica decisiones HITL y feedback recibido"
        moduloPacientes -> auditMiddleware "Notifica cambios sensibles y consentimientos"
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

                deploymentNode "Contenedor LLM Local" "Docker Container" "Runtime Ollama" {
                    containerInstance servicioLLM
                }

                deploymentNode "Stack de Observabilidad" "Docker Compose" "Monitoreo" {
                    description "Prometheus, Grafana y Loki para métricas, dashboards y logs centralizados."
                }
            }

            deploymentNode "Servicios Externos en la Nube" "Internet" "Cloud" {
                softwareSystemInstance fcm
                softwareSystemInstance smtp
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

        component backend "ComponentesGeneral" {
            include *
            autoLayout lr
            description "Vista general de todos los componentes del backend."
        }

        component backend "ComponentesAutenticacion" {
            include apiGateway moduloIdentidad keycloak appMovil portalWeb auditMiddleware postgres
            autoLayout lr
            description "Flujo de autenticación, gestión de consentimientos y auditoría asociada."
        }

        component backend "ComponentesRegistro" {
            include apiGateway moduloRegistro workerSync keydb postgres auditMiddleware appMovil
            autoLayout lr
            description "Registro clínico diario con sincronización offline desacoplada."
        }

        component backend "ComponentesIA" {
            include apiGateway servicioHITL motorRecomendaciones orquestadorLLM servicioLLM postgres auditMiddleware portalWeb
            autoLayout lr
            description "Motor de IA con LLM self-hosted y flujo HITL."
        }

        component backend "ComponentesReportes" {
            include apiGateway generadorPDF workerNotif keydb minio fcm smtp postgres
            autoLayout lr
            description "Generación de reportes PDF y notificaciones asíncronas."
        }

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
                shape MobileDevicePortrait
                fontSize 28
            }

            element "Web App" {
                background #1a6fa8
                color #ffffff
                shape WebBrowser
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

            element "LLM Service" {
                background #1a6fa8
                color #ffffff
                shape RoundedBox
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
        }
    }
}
