# Pipelines CI/CD e Infra – Guía Completa

Este documento detalla el diseño de pipelines propuestos para este repositorio. Actualmente (según búsqueda) **no existen archivos de GitHub Actions** (`.github/workflows/*.yml`), por lo que aquí se proveen ejemplos listos para agregar.

## 1. Objetivos de los Pipelines
| Objetivo | Descripción |
|----------|-------------|
| Validación rápida (PR) | Levantar el stack con Docker Compose y hacer un smoke test (sin tests unitarios, según requerimiento). |
| Construcción y Publicación | Construir imágenes Docker multi‑servicio y publicarlas (GHCR o registry externo). |
| Infraestructura | Plan / Apply de Terraform para recursos Azure (RG, ACR, etc.). |
| Calidad técnica (opcional futuro) | Lint / test multi‑lenguaje (Java, Go, Node, Python, Frontend). |

## 2. Estructura Recomendada de Workflows
| Archivo | Trigger | Propósito |
|---------|---------|-----------|
| `pr-smoke.yml` | `pull_request` | Smoke test: levantar servicios y validar endpoint 200. |
| `ci-build.yml` | `push` a `main` (y tags) | Build & push imágenes Docker. |
| `infra-plan.yml` | `pull_request` sobre `infra/**` | `terraform init/validate/plan`. |
| `infra-apply.yml` | `workflow_dispatch` (manual) | `terraform apply` (controlado). |

(Infra Plan y Apply se pueden combinar con condiciones, aquí se separan para claridad.)

## 3. Variables y Secretos
Mínimos para funcionar:
| Nombre | Uso | Obligatorio | Notas |
|--------|-----|-------------|-------|
| `JWT_SECRET` | Runtime smoke test (`auth-api`, `todos-api`) | Sí (si no se fija valor inline) | >=32 chars. |
| `AZURE_SUBSCRIPTION_ID` | Terraform / Login Azure | Sí (infra) | Variables de repositorio. |
| `AZURE_TENANT_ID` | Terraform / Login Azure | Sí | |
| `AZURE_CLIENT_ID` | OIDC App Registration | Sí | |
| `ACR_LOGIN_SERVER` | Si push a ACR | No (use GHCR si lo omites) | `miacr.azurecr.io` |
| `REGISTRY_USERNAME` | Registry externo (Docker Hub) | No | Omite para GHCR. |
| `REGISTRY_PASSWORD` | Registry externo | No | |

Si sólo usas GHCR puedes eliminar: `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, `ACR_LOGIN_SERVER` (a menos que Azure ACR sea requerido).

## 4. Convenciones de Nombres de Imágenes
Propuesto (GHCR):
```
GHCR_NAMESPACE=ghcr.io/<OWNER>
<GHCR_NAMESPACE>/microservice-app-auth-api:<sha>
<GHCR_NAMESPACE>/microservice-app-users-api:<sha>
<GHCR_NAMESPACE>/microservice-app-todos-api:<sha>
<GHCR_NAMESPACE>/microservice-app-log-message-processor:<sha>
<GHCR_NAMESPACE>/microservice-app-frontend:<sha>
```
Para Docker Hub: `<DOCKER_USER>/microservice-app-<service>:<sha>`.

## 5. Workflow 1 – Smoke Test PR (sin tests unitarios)
Requerimiento explícito: “en pull request levantar dockers y hacer consulta que devuelva 200”. Se hace login y luego GET /todos.

Crear archivo: `.github/workflows/pr-smoke.yml`
```yaml
name: PR Smoke

on:
  pull_request:
    branches: [ main, develop ]

jobs:
  smoke:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      JWT_SECRET: ${{ secrets.JWT_SECRET }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build (no push)
        run: |
          docker compose build

      - name: Start stack
        run: |
          docker compose up -d

      - name: Wait for services (auth-api, todos-api)
        run: |
          for i in {1..30}; do
            curl -s http://localhost:8000/version && echo OK && break || sleep 2
            if [ $i -eq 30 ]; then echo "auth-api no respondió"; exit 1; fi
          done
          for i in {1..30}; do
            curl -s http://localhost:8082/todos -H "Authorization: Bearer dummy" || true
            # No falla si 401: sólo verificar que el puerto responde
            nc -z localhost 8082 && echo OK && break || sleep 2
            if [ $i -eq 30 ]; then echo "todos-api no respondió"; exit 1; fi
          done

      - name: Obtener token
        id: token
        run: |
          RESP=$(curl -s -X POST http://localhost:8000/login \
            -H 'Content-Type: application/json' \
            -d '{"username":"admin","password":"admin"}')
          echo "$RESP" | jq .
          TOKEN=$(echo "$RESP" | jq -r .accessToken)
          if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then echo "No se obtuvo token"; exit 1; fi
          echo "token=$TOKEN" >> $GITHUB_OUTPUT

      - name: Smoke GET /todos
        run: |
          code=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer ${{ steps.token.outputs.token }}" \
            http://localhost:8082/todos )
          echo "HTTP Code: $code"
          test "$code" = "200"

      - name: Docker Compose Logs (solo si falla)
        if: failure()
        run: docker compose logs --no-color | tail -n 400

      - name: Shutdown
        if: always()
        run: docker compose down -v
```

Notas:
- Usa `jq` (disponible en Ubuntu) para extraer el token.
- No se ejecutan pruebas unitarias.
- Si tu `JWT_SECRET` no está configurado en Secrets deberás fijar un valor inline (NO recomendado). 

## 6. Workflow 2 – Build & Push Imágenes
Archivo: `.github/workflows/ci-build.yml`
```yaml
name: Build & Push Images

on:
  push:
    branches: [ main ]
  workflow_dispatch: {}

permissions:
  contents: read
  packages: write

jobs:
  build-push:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [auth-api, users-api, todos-api, log-message-processor, frontend]
    env:
      REGISTRY: ghcr.io/${{ github.repository_owner }}
      IMAGE_NAME: microservice-app-${{ matrix.service }}
    steps:
      - uses: actions/checkout@v4

      - name: Login GHCR
        if: !vars.ACR_LOGIN_SERVER
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Login Custom Registry
        if: vars.ACR_LOGIN_SERVER
        uses: docker/login-action@v3
        with:
          registry: ${{ vars.ACR_LOGIN_SERVER }}
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}

      - name: Build & Push
        run: |
          REG=${{ vars.ACR_LOGIN_SERVER || env.REGISTRY }}
          docker build -t $REG/${{ env.IMAGE_NAME }}:${{ github.sha }} ./${{ matrix.service }}
          docker tag $REG/${{ env.IMAGE_NAME }}:${{ github.sha }} $REG/${{ env.IMAGE_NAME }}:latest
          docker push $REG/${{ env.IMAGE_NAME }}:${{ github.sha }}
          docker push $REG/${{ env.IMAGE_NAME }}:latest
```

## 7. Workflow 3 – Terraform Plan
Archivo: `.github/workflows/infra-plan.yml`
```yaml
name: Terraform Plan

on:
  pull_request:
    paths:
      - 'infra/**'
  workflow_dispatch: {}

permissions:
  id-token: write
  contents: read

jobs:
  plan:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
            terraform_version: 1.9.5

      - name: Terraform Init
        run: terraform init -input=false

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        run: terraform plan -input=false -no-color
```

## 8. Workflow 4 – Terraform Apply (Manual)
Archivo: `.github/workflows/infra-apply.yml`
```yaml
name: Terraform Apply

on:
  workflow_dispatch:
    inputs:
      confirm:
        description: "Escribe 'APPLY' para confirmar"
        required: true
        type: string

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    if: inputs.confirm == 'APPLY'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init -input=false

      - name: Terraform Apply
        run: terraform apply -auto-approve -input=false
```

## 9. Optimización (Opcional Futuro)
| Mejora | Descripción |
|--------|-------------|
| Cache Buildx | Reusar capas Docker para servicios pesados. |
| Matrix avanzada | Paralelizar test multi-lenguaje -> sólo si se reintroducen tests. |
| Dependabot | Activar para actualizaciones de seguridad. |
| Artifact Compose Logs | Guardar logs completos en fallos de smoke. |
| SBOM / Scan | Añadir `anchore/sbom-action` o `trivy-action` para seguridad. |

## 10. Estrategia de Fail-Fast
- Smoke PR: si login falla, se cancela antes de intentar `/todos`.
- Build & Push: cada servicio independiente (matrix) – fallas parciales no bloquean los demás pero el job global aparece fallido.
- Terraform: Plan no aplica; Apply manual para ambientes controlados.

## 11. Limpieza de Secretos
Si no utilizas:
- Registry externo → elimina `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, `REGISTRY_HOST` / `ACR_LOGIN_SERVER`.
- Infra Azure → elimina workflows de Terraform (o desactiva) para simplificar.

## 12. Consideraciones de Seguridad
| Aspecto | Recomendación |
|---------|---------------|
| Secretos | Usar `secrets` no `vars` para cualquier credencial. |
| JWT_SECRET | Rotar periódicamente; evitar exponer en logs. |
| Principio mínimo | OIDC app con permisos sólo de ACR y RG necesarios. |
| Pull Requests forks | En smoke, evitar usar secretos si se habilitan PRs desde forks (usar `pull_request_target` con cautela). |

## 13. Reutilización Local (Debug)
Puedes simular pasos clave:
```bash
# Build local
docker compose build

# Smoke local manual
docker compose up -d
curl -X POST http://127.0.0.1:8000/login -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}'
# export TOKEN=...
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8082/todos
```

## 14. Errores Comunes y Diagnóstico
| Síntoma | Causa probable | Acción |
|---------|----------------|--------|
| 503 en login durante smoke | Users API tardando / breaker abierto | Revisar logs `auth-api`, aumentar timeout | 
| Curl 000 / conexión rechazada | Servicio aún no listo | Incrementar bucle de espera o healthcheck explícito |
| Plan Terraform falla en backend | Backend remoto sin configurar | Copiar `backend.tf.example` → `backend.tf` con datos correctos |
| Push GHCR falla | Falta permiso `packages: write` | Añadir permisos workflow |

## 15. Roadmap Propuesto
1. (Hecho) Smoke básico PR.
2. Añadir paso de lint multi-lenguaje (paralelo) – opcional.
3. Integrar escaneo de vulnerabilidades contenedores.
4. Publicar SBOM.
5. Añadir pipeline de CD (deploy en Azure Web Apps / AKS) consumiendo imágenes.
6. Tests contractuales antes de merge.

## 16. Resumen
Los pipelines propuestos cubren validación rápida (Smoke), construcción de artefactos (imágenes Docker), y gestión de infraestructura (Terraform) con OIDC. Están diseñados para ser incrementales y seguros: aplican principios de fail-fast, ejecución segmentada por responsabilidad y mínima superficie de secretos.

---
Fin del documento.

