# Microservice App - PRFT Devops Training

This is the application you are going to use through the whole traninig. This, hopefully, will teach you the fundamentals you need in a real project. You will find a basic TODO application designed with a [microservice architecture](https://microservices.io). Although is a TODO application, it is interesting because the microservices that compose it are written in different programming language or frameworks (Go, Python, Vue, Java, and NodeJS). With this design you will experiment with multiple build tools and environments. 

## Components
In each folder you can find a more in-depth explanation of each component:

1. [Users API](/users-api) is a Spring Boot application. Provides user profiles. At the moment, does not provide full CRUD, just getting a single user and all users.
2. [Auth API](/auth-api) is a Go application, and provides authorization functionality. Generates [JWT](https://jwt.io/) tokens to be used with other APIs.
3. [TODOs API](/todos-api) is a NodeJS application, provides CRUD functionality over user's TODO records. Also, it logs "create" and "delete" operations to [Redis](https://redis.io/) queue.
4. [Log Message Processor](/log-message-processor) is a queue processor written in Python. Its purpose is to read messages from a Redis queue and print them to standard output.
5. [Frontend](/frontend) Vue application, provides UI.

## Architecture

Take a look at the components diagram that describes them and their interactions.
![microservice-app-example](/arch-img/Microservices.png)

---

## Extended Documentation (Spanish / Español)
The following in-depth documentation files have been consolidated under the `DOCS/` directory (Spanish versions):

| Topic | File |
|-------|------|
| Project Overview (visión completa, ejecución, patrones) | [DOCS/PROJECT_OVERVIEW_ES.md](DOCS/PROJECT_OVERVIEW_ES.md) |
| Cache-Aside Pattern (implementación en todos-api) | [DOCS/CACHE_ASIDE.md](DOCS/CACHE_ASIDE.md) |
| Circuit Breaker (Go auth-api & Python log-processor) | [DOCS/CIRCUIT_BREAKER.md](DOCS/CIRCUIT_BREAKER.md) |
| CI/CD & Infra Pipelines (workflows propuestos) | [DOCS/PIPELINES.md](DOCS/PIPELINES.md) |
| Security Improvements & Hardening Roadmap | [DOCS/SECURITY_IMPROVEMENTS.md](DOCS/SECURITY_IMPROVEMENTS.md) |

> NOTE: The original `CACHE_ASIDE.md` and `SECURITY_IMPROVEMENTS.md` at repository root are kept temporarily for backward compatibility. Prefer the versions inside `DOCS/` and you may remove the root files later if no external references depend on them.

---

## Quickstart with Docker Compose

We added Dockerfiles for each microservice and a top-level `docker-compose.yml` to run the whole stack locally, including Redis and Zipkin.

### 1) Prepare environment

Create a `.env` file from the example and adjust the secret (must be at least 32 chars):

```bat
copy .env.example .env
REM Edit .env and set a strong JWT_SECRET (min 32 chars)
```

### 2) Start the stack

```bat
docker compose up -d --build
```

Services and ports:
- frontend: http://127.0.0.1:8080
- auth-api: http://127.0.0.1:8000
- todos-api: http://127.0.0.1:8082
- users-api: http://127.0.0.1:8083
- redis: 127.0.0.1:6379
- zipkin: http://127.0.0.1:9411

Logs:
```bat
docker compose logs -f
```

Stop:
```bat
docker compose down
```

### 3) Smoke test end-to-end (optional)
Get a token:
```bat
curl -X POST http://127.0.0.1:8000/login ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"admin\",\"password\":\"admin\"}"
```
Use the `accessToken` to call Todos API:
```bat
set TOKEN=PASTE_YOUR_ACCESS_TOKEN_HERE
curl -H "Authorization: Bearer %TOKEN%" http://127.0.0.1:8082/todos
curl -X POST -H "Authorization: Bearer %TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"content\":\"demo from curl\"}" ^
  http://127.0.0.1:8082/todos
```
You should see new log messages in `log-message-processor` container and traces in Zipkin.

### 4) Frontend
Open http://127.0.0.1:8080 and login with one of the example users:
- admin / admin
- johnd / foo
- janed / ddd

---

## Local development (without Docker)
Refer to each service README for per-service commands. In short:
- Users API: `mvnw.cmd clean install` then `java -jar target/users-api-0.0.1-SNAPSHOT.jar`
- Auth API: `go build` then run with `AUTH_API_PORT`, `USERS_API_ADDRESS`, `JWT_SECRET`
- Todos API: `npm install` and `npm start` (requires `JWT_SECRET`, Redis)
- Log Processor: `pip install -r requirements.txt` then run with Redis env vars
- Frontend: `npm install` then `npm start` (dev server + proxies)

Quick controller test for TODOs API (no server required):
```bat
cd todos-api
node tests\test_todoController.js
```

---

You should also:

For this project, you must work on both the development and operations sides,
considering the different aspects so that the project can be used by
an agile team. Initially, you must choose the agile methodology to use.
Aspects to consider for the development of the workshop:
1. 2.5% Branching strategy for developers
2. 2.5% Branching strategy for operations
3. 15.0% Cloud design patterns (minimum two)
4. 15.0% Architecture diagram
5. 15.0% Development pipelines (including scripts for tasks that require them)
6. 5.0% Infrastructure pipelines (including scripts for tasks that require them)


7. 20.0% Infrastructure implementation


8. 15.0% Live demonstration of changes in the pipeline


9. 10.0% Delivery of results: must include the necessary documentation
for all developed elements.



Regarding patterns, consider using two of the following: cache aside,
circuit breaker, autoscaling, federated identity.

---

## Infra & DevOps

CI/CD and Terraform are included to build/publish images and provision Azure resources (RG + ACR).

### CI (GitHub Actions)
- Workflow: `.github/workflows/ci-docker.yml` builds and pushes images for `auth-api`, `users-api`, `todos-api`, `log-message-processor`, and `frontend` to GHCR under `ghcr.io/<org>/microservice-app-example-<service>` on pushes to `main`.
- Uses built-in `GITHUB_TOKEN`; no extra secrets required for GHCR.

### IaC (Terraform on Azure)
- Root: `infra/`
- Backend template: `infra/backend.tf.example` (copy to `infra/backend.tf` and fill Storage Account/Container details)
- Example variables: `infra/terraform.tfvars.example` (set `location`, `environment`, optionally `acr_sku`)
- Modules:
  - `infra/modules/resource-group` creates the resource group
  - `infra/modules/acr` creates Azure Container Registry

Local usage:
```bat
cd infra
copy backend.tf.example backend.tf
copy terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

### Terraform in CI (OIDC to Azure)
- Workflow: `.github/workflows/terraform.yml` logs in to Azure via OIDC and runs `init/validate/plan`; supports manual Apply via workflow dispatch input.

GitHub configuration (Repository Settings → Variables):
- `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`
- Optional: `AZURE_LOCATION` (e.g., `eastus`), `ENVIRONMENT` (e.g., `dev`)

Azure prerequisites:
- Create a Storage Account and a `tfstate` container for Terraform backend; update `infra/backend.tf.example` and copy to `infra/backend.tf`.
- Create a Federated Credential on an Azure AD App registration (client id above) for your repo (`token.actions.githubusercontent.com`) so GitHub can OIDC login.

### Container images (Azure ACR)
- Workflow: `.github/workflows/ci-docker.yml` builds and pushes images to ACR.
- Required repo variables: `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `ACR_LOGIN_SERVER` (e.g., `myregistry.azurecr.io`).