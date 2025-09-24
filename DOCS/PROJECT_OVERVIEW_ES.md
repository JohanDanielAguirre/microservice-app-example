# Microservice App Example – Documentación Integral (ES)

## 1. Descripción General
Aplicación de ejemplo orientada a entrenamiento DevOps y patrones de arquitectura cloud-native. Implementa una solución TODO multi‑usuario con autenticación JWT, microservicios escritos en distintos lenguajes (Java, Go, Node.js, Python, Vue) y componentes de observabilidad (Zipkin) y mensajería ligera (Redis). 

Objetivos educativos:
- Practicar CI/CD multi‑lenguaje.
- Aplicar patrones (Cache-Aside, Circuit Breaker – configurado en Auth API, Pub/Sub simple con Redis).
- Infraestructura como código (Terraform sobre Azure) y empaquetado en contenedores.
- Ejecución local orquestada con Docker Compose.

---
## 2. Arquitectura Lógica

Flujo principal (alto nivel):
1. Cliente (browser) carga el **Frontend (Vue)**.
2. Usuario se autentica contra **Auth API (Go)** → genera JWT.
3. Frontend usa el token JWT para llamar a **Todos API (Node.js)** y listar/crear/borrar TODOs.
4. Todos API aplica patrón **Cache-Aside** (caché en memoria por usuario; opcional Redis para log/cola y futura caché distribuida).
5. Operaciones de creación/borrado publican mensajes en un canal Redis ("log_channel").
6. **Log Message Processor (Python)** suscribe y procesa/imprime esos eventos (demostración de procesamiento asíncrono).
7. **Users API (Java Spring Boot)** provee datos de perfiles consumidos por Auth API para validar usuarios (credenciales embebidas / data.sql).
8. **Zipkin** recolecta trazas distribuidas (servicios envían spans vía HTTP).

Componentes y responsabilidades:
- Frontend (Vue): UI, login, gestión de TODOs.
- Auth API (Go): login → JWT; aplica Circuit Breaker simple al llamar Users API (configurable vía vars CB_*).
- Users API (Spring Boot): usuarios de ejemplo (catálogo en memoria / data.sql).
- Todos API (Node.js + memory-cache + Redis Pub/Sub): CRUD + Cache-Aside + publicación de eventos.
- Log Message Processor (Python): consumidor de canal Redis.
- Redis: canal de eventos y potencial caché distribuida.
- Zipkin: trazas.

---
## 3. Diagrama (Descripción textual para diagramar)

Cliente Web → Frontend (Vue SPA)
Frontend → (POST /login) → Auth API (Go)
Auth API → (GET /users /users/{id}) → Users API (Spring) [con Circuit Breaker]
Frontend → (Bearer JWT) → Todos API (Node)
Todos API → (Cache-aside: consulta caché en memoria / carga inicial) → Fuente de datos en memoria (semilla)
Todos API → (PUBLISH evento create/delete) → Redis (canal log_channel)
Log Message Processor → (SUBSCRIBE log_channel) → Redis
Todos API & Auth API & Users API & Log Processor → (envío spans) → Zipkin

Puedes convertirlo a un diagrama (p.ej. Mermaid):
```mermaid
graph TD
A[Cliente Browser] --> B[Frontend Vue]
B --> C[Auth API (Go)]
C --> D[Users API (Spring Boot)]
B --> E[Todos API (Node.js)]
E -->|Cache Miss| F[(Cache Memoria Usuario)]
F --> E
E -->|Pub/Sub create/delete| G[(Redis Canal log_channel)]
H[Log Message Processor (Python)] --> G
C --> I[Zipkin]
D --> I
E --> I
H --> I
```

---
## 4. Repositorio y Estructura Clave
- `docker-compose.yml`: orquesta todo el stack local (incluye redis y zipkin).
- `auth-api/`: Go (JWT + CB + tracing).
- `users-api/`: Java Spring Boot (mvn wrapper, endpoints usuarios, data.sql).
- `todos-api/`: Node.js (CRUD TODOs + memory-cache + Redis publish + tracing + test script).
- `log-message-processor/`: Python (suscriptor Redis + tracing + circuit breaker rudimentario contra Zipkin si configurado).
- `frontend/`: Vue (login, listado y operaciones TODO; llamadas a APIs internas por nombre de servicio en red docker).
- `infra/`: Terraform Azure (RG, ACR, módulos, backend remoto S3-like en Azure Storage).
- `CACHE_ASIDE.md`: explicación detallada patrón Cache-Aside implementado.

---
## 5. Ejecución Rápida con Docker Compose
Requisitos: Docker Desktop / Engine.

1. Copia ejemplo de variables:
```bat
copy .env.example .env
```
2. Edita `.env` y define `JWT_SECRET` (≥32 caracteres).
3. Levanta servicios:
```bat
docker compose up -d --build
```
4. Puertos:
- Frontend: http://127.0.0.1:8080
- Auth API: http://127.0.0.1:8000
- Todos API: http://127.0.0.1:8082
- Users API: http://127.0.0.1:8083
- Zipkin: http://127.0.0.1:9411
- Redis: 6379

5. Logs unificados:
```bat
docker compose logs -f
```
6. Detener:
```bat
docker compose down
```

### 5.1 Smoke Test (cmd.exe)
Obtener token:
```bat
curl -X POST http://127.0.0.1:8000/login ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"admin\",\"password\":\"admin\"}"
```
Listar TODOs:
```bat
set TOKEN=PEGAR_TOKEN
curl -H "Authorization: Bearer %TOKEN%" http://127.0.0.1:8082/todos
```
Crear y volver a listar:
```bat
curl -X POST -H "Authorization: Bearer %TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"content\":\"tarea demo\"}" ^
  http://127.0.0.1:8082/todos
```
Ver trazas en Zipkin UI.

---
## 6. Ejecución por Servicio (Desarrollo Local sin Compose)

| Servicio | Pasos rápidos |
|----------|---------------|
| Users API | `cd users-api && mvnw.cmd clean install && java -jar target/users-api-0.0.1-SNAPSHOT.jar` |
| Auth API | `cd auth-api && go build -o auth-api . && set JWT_SECRET=... && set USERS_API_ADDRESS=http://localhost:8083 && auth-api.exe` |
| Todos API | `cd todos-api && npm install && set JWT_SECRET=... && npm start` |
| Log Processor | `cd log-message-processor && pip install -r requirements.txt && python main.py` |
| Frontend | `cd frontend && npm install && npm run dev` |

Considera exportar también variables de Redis si deseas usarlo fuera de Compose.

---
## 7. Variables de Entorno Clave

Global / Comunes:
- `JWT_SECRET`: Secreto para firmar/verificar JWT (obligatorio). Mínimo 32 chars.

Auth API:
- `AUTH_API_PORT` (default 8000)
- `USERS_API_ADDRESS` (URL de Users API)
- `CB_*` (parámetros Circuit Breaker: `CB_ENABLED`, `CB_TIMEOUT_MS`, `CB_RESET_TIMEOUT_MS`, `CB_ERROR_THRESHOLD`, `CB_REQUEST_TIMEOUT_MS`)
- `ZIPKIN_URL` (endpoint ingestion spans) 

Users API:
- `SERVER_PORT` (8083 por defecto)
- `SPRING_ZIPKIN_BASEURL`

Todos API:
- `TODO_API_PORT` (8082)
- `REDIS_URL` o (`REDIS_HOST`, `REDIS_PORT`)
- `REDIS_CHANNEL` (log_channel)
- `ZIPKIN_URL`
- `TODO_CACHE_TTL` (si se extiende a Redis, TTL sugerido)

Log Message Processor:
- `REDIS_URL` / host/port
- `REDIS_CHANNEL`
- `ZIPKIN_URL`
- `CB_ZIPKIN_*` (Breaker hacia Zipkin)

Frontend:
- `PORT` (8080)
- `AUTH_API_ADDRESS`
- `TODOS_API_ADDRESS`
- `ZIPKIN_URL`

Infra / Azure:
- `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `ACR_LOGIN_SERVER` (para pipelines de build Terraform/ACR).

---
## 8. Patrones Implementados

1. Cache-Aside: en `todos-api` (ver `CACHE_ASIDE.md`). Lectura primero en caché; miss → construir semilla y cachear; escrituras actualizan/invalidan en memoria.
2. Circuit Breaker: en `auth-api` para llamadas a Users API (variables CB_*). En Python log-processor existe manejo similar para fallos Zipkin configurable.
3. Pub/Sub (Event-driven simplificado): Todos API publica eventos de operaciones a Redis canal `log_channel`; log-message-processor suscribe.
4. Tracing Distribuido: todos los servicios envían spans a Zipkin.

Posibles ampliaciones (no activas): Autoscaling (en plataforma cloud), Federated Identity (OIDC externo), Rate Limiting.

---
## 9. Testing

Actualmente:
- Users API: pruebas de integración (directorio `users-api/src/test`). Ejecutar: `mvnw.cmd test`.
- Todos API: script simple de prueba de controlador (`node tests/test_todoController.js`) si está presente (menciona README, añadir tests adicionales recomendado).

Sugerencias de mejora:
- Añadir Jest/Supertest para endpoints Node.
- Test de contrato para Auth API (Go) con `httptest`.
- Pruebas de integración dockerizadas (GitHub Actions) levantando stack y validando health (status 200) en endpoints.

---
## 10. CI/CD (Resumen Esperado)

Workflows (no listados aquí si aún no existen en repo, propuesto):
1. Build & Lint (pull_request + push):
   - Go build + `go test ./...`
   - Maven build + tests
   - Node install + lint/test
   - Python lint (flake8) + pruebas (si se agregan)
   - Frontend build (webpack / vue) para asegurar compilación.
2. Docker Multi-image:
   - Construye y etiqueta imágenes `ghcr.io/<owner>/microservice-app-<service>:<sha>`
   - Reutiliza caché de build (acciones `cache`/`buildx`).
3. Infra Terraform Plan (pull_request) y Apply (push a main / manual).
4. Smoke E2E job: `docker compose up -d`, esperar puertos y curl `GET /todos` tras login (assert 200).

Secrets/Variables mínimos:
- `JWT_SECRET` (si se requiere en runtime del smoke test; puede inyectarse via env). 
- Para ACR (si no GHCR): `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, `REGISTRY_HOST`.
- Azure OIDC: `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`.

Si ya no están presentes y no se usarán (p.ej. registry externo), se pueden eliminar de pipeline.

---
## 11. Infraestructura como Código (Terraform)

Directorio `infra/` agrupa módulos:
- `modules/resource-group`: Crea Resource Group.
- `modules/acr`: Azure Container Registry.
- `modules/redis` (si existe en evolución; actual revisar; se provee stub para potencial Redis administrado) .

Pasos:
```bat
cd infra
copy backend.tf.example backend.tf
copy terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```
Actualizar `backend.tf` con Storage Account / Container para estado remoto.

---
## 12. Observabilidad

- Trazas: Zipkin UI (spans con operación de login, CRUD todos, etc.).
- Logs: `docker compose logs -f` + mensajes procesados en contenedor `log-message-processor`.
- Métricas (no implementadas aún): sugerido añadir Prometheus endpoint en cada servicio + dashboards.

---
## 13. Seguridad / Hardening (Líneas Base)

- Segregar secretos mediante variables de entorno (no versionar `.env`).
- Forzar longitud mínima `JWT_SECRET` y rotación programada.
- Añadir validaciones de input (todos-api ya valida contenido, expandir). 
- Dependabot / Renovate para actualización de dependencias.
- Contenedores: usar versiones mínimas (alpine) donde sea viable (optimización futura).
- Firmado de imágenes: Cosign (futuro).

---
## 14. Estrategia de Branching (Sugerida)

- `main`: estable, deployable.
- `develop` (opcional si se adopta Git Flow ligero).
- `feature/*`: nuevas funcionalidades.
- `hotfix/*`: correcciones urgentes desde `main`.
- Pull Request obligatorio → dispara build + smoke test.

Infra:
- `infra/*` ramas específicas para cambios grandes de IaC con revisiones separadas.

---
## 15. Extensiones Futuras

| Mejora | Descripción |
|--------|-------------|
| Redis como caché real de TODOs | Reemplazar memoria local → coherencia multi réplica. |
| Persistencia DB | Introducir Postgres para TODOs (fuente de verdad) + Cache-Aside real. |
| Métricas Prometheus | Exponer `/metrics` y dashboard Grafana. |
| Canary / Blue-Green | Estrategia de despliegue progresivo. |
| Seguridad avanzada | OIDC externo, roles/grants finos, rate limiting. |
| Tests contractuales | Pact entre frontend y APIs. |

---
## 16. FAQ Rápido

**Por qué los TODOs no persisten tras reinicio?** Caché en memoria → se reinicializa.
**Puedo escalar todos-api?** Sí, pero cada réplica tendría caché aislada (usar Redis para compartir).
**Dónde está implementado Cache-Aside?** `todos-api/todoController.js` (ver explicación en `CACHE_ASIDE.md`).
**Cómo veo eventos de creación/borrado?** Logs del contenedor `log-message-processor`.
**Cómo verifico trazas?** Zipkin UI en puerto 9411.

---
## 17. Comandos Útiles (Cheat Sheet)

Rebuild sólo un servicio:
```bat
docker compose build todos-api && docker compose up -d todos-api
```
Inspeccionar logs de un servicio:
```bat
docker compose logs -f todos-api
```
Entrar a un contenedor:
```bat
docker exec -it todos-api sh
```
Recrear stack limpio:
```bat
docker compose down -v && docker compose up -d --build
```

---
## 18. Licencia
Ver archivo `LICENSE` en la raíz del repositorio.

---
## 19. Resumen Ejecutivo
Aplicación poliglota de microservicios para entrenamiento: demuestra autenticación, cache-aside, tracing distribuido, orquestación con Docker Compose, y base para CI/CD e Infra como Código en Azure. Sirve como plantilla para extender hacia un producto más robusto con persistencia real, observabilidad avanzada y despliegues automatizados.

---
Fin del documento.

