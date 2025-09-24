# Users API

This service is written in Java with SpringBoot. It provides simple API to retrieve user data and supports JWT authentication with role-based access control.

## API Endpoints

- `GET /users` - list all users (requires ADMIN role)
- `GET /users/:username` - get a user by name (requires valid JWT token)
- `GET /health` - health check endpoint
- `GET /actuator/health` - Spring Boot actuator health endpoint

## Architecture & Design Patterns

### Microservice Architecture
This service is part of a microservices architecture that includes:
- **Auth API** (Go) - Authentication and Circuit Breaker pattern
- **Todos API** (Node.js) - Cache-Aside pattern with Redis
- **Users API** (Java/Spring Boot) - User data management
- **Frontend** (Vue.js) - Web interface
- **Log Message Processor** (Python) - Event processing

### Security Implementation
- **JWT Authentication**: Validates JWT tokens signed by Auth API
- **Role-based Authorization**: ADMIN role required for listing all users
- **HTTPS**: All communications secured with TLS
- **Input Validation**: Request validation and sanitization

### Integration Points
- **Authentication Flow**: Works with Auth API for JWT token validation
- **Internal Communication**: Accessible internally by Auth API for user validation
- **Circuit Breaker**: Auth API implements Circuit Breaker when calling this service

## Configuration

The service scans environment for variables:
- `JWT_SECRET` - secret value for JWT token processing. Must be the same amongst all components.
- `SERVER_PORT` - the port the service takes (default: 8083).
- `SPRING_ZIPKIN_BASEURL` - Zipkin tracing endpoint (optional).

### Environment Variables in Production
```
JWT_SECRET=your-super-secret-jwt-key-here-make-it-long-and-secure
SERVER_PORT=8083
SPRING_ZIPKIN_BASEURL=""
```

## Building

### Local Development
```bash
./mvnw clean install
```

### Docker Build
```bash
docker build -t users-api:latest .
```

### Production Build (Azure Container Registry)
```bash
# Login to ACR
az acr login --name microserviceappexampledevacr

# Build and push
docker build -t microserviceappexampledevacr.azurecr.io/microservice-app-example-users-api:latest .
docker push microserviceappexampledevacr.azurecr.io/microservice-app-example-users-api:latest
```

## Running

### Local Development
```bash
JWT_SECRET=PRFT SERVER_PORT=8083 java -jar target/users-api-0.0.1-SNAPSHOT.jar
```

### Docker Run
```bash
docker run -p 8083:8083 \
  -e JWT_SECRET=PRFT \
  -e SERVER_PORT=8083 \
  users-api:latest
```

### Production Deployment
The service is deployed on **Azure Container Apps** with the following configuration:
- **CPU**: 0.5 cores
- **Memory**: 1Gi
- **Scaling**: HTTP-based auto-scaling (up to 50 concurrent requests)
- **Ingress**: Internal only (not externally accessible)
- **Identity**: Managed Identity for Azure Container Registry access

## Usage

### Authentication Flow
1. Get JWT token from Auth API:
```bash
curl -X POST https://msapp-dev-auth.wonderfulocean-898ef9b4.eastus.azurecontainerapps.io/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin"}'
```

2. Use token to access Users API:
```bash
curl -X GET -H "Authorization: Bearer $token" \
  http://127.0.0.1:8083/users/admin
```

### Production URLs
- **Internal URL** (used by Auth API): `http://msapp-dev-users`
- **External access**: Not available (internal service only)

### Sample Responses

#### Get User by Username
```bash
GET /users/admin
```
Response:
```json
{
  "username": "admin",
  "firstname": "Foo",
  "lastname": "Bar",
  "role": "ADMIN"
}
```

#### Health Check
```bash
GET /health
```
Response:
```json
{
  "status": "UP"
}
```

## Infrastructure as Code

### Terraform Configuration
Located in `infra/modules/aca/main.tf`:

```hcl
resource "azurerm_container_app" "users_api" {
  name                         = "msapp-dev-users"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  
  template {
    container {
      name   = "users-api"
      image  = "${var.acr_login_server}/microservice-app-example-users-api:latest"
      cpu    = 0.5
      memory = "1Gi"
      
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
      env {
        name  = "SERVER_PORT"
        value = "8083"
      }
    }
  }
  
  ingress {
    external_enabled = false  # Internal service only
    target_port      = 8083
  }
}
```

### Deployment Commands
```bash
cd infra
terraform init
terraform plan
terraform apply -target=module.aca.azurerm_container_app.users_api
```

## CI/CD Pipeline

### GitHub Actions Workflow
Located in `.github/workflows/`:
- **Trigger**: Push to develop/main branches
- **Build**: Maven build and Docker image creation
- **Deploy**: Push to Azure Container Registry
- **Infrastructure**: Terraform apply for Container Apps

### Pipeline Stages
1. **Code Checkout**
2. **Java/Maven Build**
3. **Docker Image Build**
4. **Push to Azure Container Registry**
5. **Infrastructure Deployment**
6. **Health Check Verification**

## Security Features

### JWT Authentication Filter
- **Class**: `JwtAuthenticationFilter.java`
- **Function**: Validates JWT tokens on every request
- **Claims Validation**: Checks token signature and expiration

### Authorization
- **Role-based**: ADMIN role required for sensitive operations
- **Token Validation**: All endpoints require valid JWT except health checks

### Security Headers
- **CORS**: Configured for microservices communication
- **Content Security**: Input validation and sanitization

## Monitoring & Observability

### Health Checks
- **Spring Boot Actuator**: `/actuator/health`
- **Custom Health**: `/health`
- **Azure Container Apps**: Built-in health monitoring

### Logging
- **Application Logs**: Available through Azure Container Apps logs
- **Access Logs**: HTTP request/response logging

### Monitoring Commands
```bash
# View container logs
az containerapp logs show --name msapp-dev-users \
  --resource-group microservice-app-example-dev-rg --follow

# Check container status
az containerapp show --name msapp-dev-users \
  --resource-group microservice-app-example-dev-rg \
  --query "{Name:name, Status:properties.runningStatus}"
```

## Testing

### Unit Tests
```bash
./mvnw test
```

### Integration Testing
```bash
# Test with Auth API integration
curl -X POST https://msapp-dev-auth.wonderfulocean-898ef9b4.eastus.azurecontainerapps.io/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin"}'

# Use returned token for users API
export TOKEN="your-jwt-token-here"
curl -X GET -H "Authorization: Bearer $TOKEN" \
  http://msapp-dev-users.internal:8083/users/admin
```

### Circuit Breaker Testing
The Auth API implements Circuit Breaker pattern when calling this service:
- **Error Threshold**: 3 consecutive failures
- **Timeout**: 5000ms for circuit open state
- **Recovery**: Automatic after timeout period

## Dependencies

Here you can find the software required to run this microservice, as well as the version we have tested:

| Dependency | Version | Purpose |
|------------|---------|---------|
| Java | openJDK8 | Runtime environment |
| Spring Boot | 2.x | Web framework |
| Spring Security | 5.x | JWT authentication |
| Maven | 3.6+ | Build tool |
| Docker | 20.x+ | Containerization |
| Azure CLI | 2.x+ | Azure deployment |
| Terraform | 1.5+ | Infrastructure as Code |

## Troubleshooting

### Common Issues

#### 1. JWT Token Validation Failed
```
Error: Invalid token
Solution: Ensure JWT_SECRET matches across all services
```

#### 2. Service Unavailable (503)
```
Error: Circuit Breaker open
Solution: Check Auth API circuit breaker status and logs
```

#### 3. Container App Not Starting
```bash
# Check container logs
az containerapp logs show --name msapp-dev-users \
  --resource-group microservice-app-example-dev-rg

# Check environment variables
az containerapp show --name msapp-dev-users \
  --resource-group microservice-app-example-dev-rg \
  --query "properties.template.containers[0].env"
```

## Development Team & Maintenance

### Architecture Decisions
- **Internal Service**: Not exposed externally for security
- **JWT Integration**: Seamless authentication with Auth API
- **Container Apps**: Chosen for serverless scaling and Azure integration

### Future Improvements
- [ ] Add Redis caching for user data
- [ ] Implement user management endpoints (POST, PUT, DELETE)
- [ ] Add comprehensive audit logging
- [ ] Implement database persistence (currently in-memory)

---

**Project**: Microservice App Example  
**Environment**: Azure Container Apps  
**Last Updated**: September 2025  
**Status**: Production Ready ✅