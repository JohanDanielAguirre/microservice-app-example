# Seguridad y Mejores Prácticas – Estado Actual y Roadmap

Este documento amplía el archivo original `SECURITY_IMPROVEMENTS.md` (que permanece en la raíz para compatibilidad) y consolida el estado de seguridad, medidas ya aplicadas, brechas pendientes y un roadmap recomendado.

## 1. Objetivos de Seguridad del Proyecto
- Proteger secretos (JWT) y eliminar credenciales hardcodeadas.
- Reducir superficie de ataque (headers, CORS, validaciones de entrada).
- Aumentar robustez (circuit breaker, aislamiento de fallos, control concurrente safe).
- Facilitar monitoreo y trazabilidad (logs estructurados + tracing Zipkin).
- Preparar base para escalamiento seguro (Infra como código + contenedores).

## 2. Medidas Ya Implementadas (Resumen Consolidado)
| Categoría | Medida | Estado | Evidencia |
|-----------|--------|--------|----------|
| Gestión de secretos | `JWT_SECRET` requerido en servicios críticos | ✅ | `auth-api/main.go`, `todos-api/server.js` (validaciones) |
| Eliminación hardcode | Claves JWT eliminadas del código | ✅ | Historial de commits (no presente en código actual) |
| Dependencias seguras | Migración a `golang-jwt/jwt/v4`, actualización Spring Boot | ✅ | `go.mod`, `pom.xml` |
| Headers de seguridad | XSS, X-Frame, HSTS, no sniff | ✅ | `auth-api/main.go` (middleware Secure) |
| CORS restringido | Orígenes explícitos localhost/127.0.0.1 | ✅ | `auth-api/main.go` |
| Validación de entrada | Campos requeridos login / TODOs | ✅ | `auth-api/main.go`, `todos-api/todoController.js` |
| Errores consistentes | `HTTPErrorHandler` + códigos claros | ✅ | `auth-api/main.go` |
| Concurrencia segura | Mutex en cache TODOs | ✅ | `todos-api/todoController.js` |
| Circuit Breaker | Protección hacia Users API y Zipkin | ✅ | `auth-api/main.go`, `log-message-processor/main.py` |
| Logging mejorado | Errores con contexto | ✅ | Código Go / Node / Python |
| Segregación de responsabilidades | Lógica separada de HTTP | ✅ | `auth-api/user.go` |

## 3. Análisis de Superficie de Ataque (Actual)
| Vector | Riesgo | Mitigación Actual | Brecha Potencial |
|--------|--------|-------------------|------------------|
| JWT (firma) | Fuga / fuerza bruta | Secreto >=32 chars (recomendado) | No hay rotación / no hay TTL configurable dinámicamente |
| Cache en memoria | Exposición de datos si dump | Acceso sólo interno contenedor | No cifrado, no invalidación distribuida |
| Falta DB real | Pérdida de persistencia | Datos efímeros (diseño didáctico) | Sin auditoría/consistencia real |
| Redis (cola) | Lectura no autorizada | Solo red interna docker-compose | Falta AUTH/TLS si expuesto fuera |
| Tracing (Zipkin) | Datos sensibles en spans | Campos limitados | No sanitización formal de payloads |
| CSRF | Sesión no usada (JWT) | APIs puras token-based | No hay verificación anti replay tokens |
| Rate limiting | Abuso/brute force | No implementado | Implementar capa de limitación (Nginx / lib) |
| Seguridad de imágenes | Vulnerabilidades base | No escaneo CI | Añadir Trivy/Grype |
| Supply chain | Dependencias comprometidas | Actualizaciones manuales | Activar Dependabot / firma imágenes |

## 4. Recomendaciones Inmediatas (Prioridad Alta)
1. Pipeline de análisis de vulnerabilidades (Trivy) sobre imágenes generadas.
2. Activar Dependabot / Renovate para los gestores:
   - Maven, Go Modules, npm, pip, Docker.
3. Añadir Rate Limiting (ej: para `/login`).
4. Rotación y versionado de `JWT_SECRET` (introducir `kid` en header JWT para rotaciones progresivas).
5. Reforzar CORS en ambientes productivos (dominios reales en vez de `localhost`).

## 5. Recomendaciones de Mediano Plazo
| Tema | Acción | Beneficio |
|------|--------|-----------|
| Observabilidad seguridad | Métricas de intentos fallidos login | Detección brute force |
| Auditoría acceso | Añadir claims mínimos + tracking ID | Trazabilidad y cumplimiento |
| Endurecimiento contenedores | Imágenes base slim/alpine + non-root user | Menor superficie |
| Firma de imágenes | Cosign + verificación en deploy | Integridad supply chain |
| Config centralizada | Vault / SSM para secretos | Gestión y rotación segura |
| Límite payloads | Configurar tamaño máximo request (Go/Echo & Node) | Mitiga DoS por cuerpo grande |

## 6. Roadmap de Evolución (Secuencial Propuesto)
| Fase | Objetivo | Entregable |
|------|----------|-----------|
| 1 | Escaneo básico | Workflow con Trivy SBOM + severity gates |
| 2 | Dependabot | PR automáticas versión dependencias |
| 3 | Rate Limiting | Middleware / reverse proxy con límites |
| 4 | Non-root containers | Dockerfiles ajustados + tests ejecución |
| 5 | Rotación JWT | Soporte multi-key (`kid`) y revocación básica |
| 6 | Firma y verificación | Pipeline Cosign y política admisión (OPA) |
| 7 | Métricas seguridad | Endpoint `/metrics` con contadores login fallidos |
| 8 | Vault integration | Reemplazar variables directas en runtime |

## 7. Checklist Rápida (Hardening Futuro)
- [ ] Todas las imágenes ejecutan como usuario no root.
- [ ] Escaneo de CVEs automático (alto/crit bloquea merge).
- [ ] Registro de intentos de login fallidos con métrica.
- [ ] Limite de tamaño de request global (ej. 1MB).
- [ ] Sanitización de logs (no tokens/token recortado).
- [ ] Política de retención de logs definida.
- [ ] Rotación `JWT_SECRET` documentada y automatizada.
- [ ] Requerir HTTPS/TLS en despliegue cloud (reverse proxy / ingress con certs). 
- [ ] Política de expiración de tokens < 24h (actual: 72h) configurable.

## 8. Modelo de Amenazas (Simplificado STRIDE)
| Categoría | Ejemplo | Mitigación Actual | Mejora |
|-----------|---------|-------------------|--------|
| Spoofing | Suplantar identidad de usuario | JWT con firma | Añadir expiración corta + revocación |
| Tampering | Modificar mensajes en tránsito | (Local dev sin TLS) | HTTPS en despliegue productivo |
| Repudiation | Usuario niega acción | Logs básicos | Añadir IDs de correlación, persistencia |
| Information Disclosure | Exposición de datos en spans | Spans limitados | Revisar sanitización de logs/spans |
| Denial of Service | Flood a `/login` | No mitigación | Rate limiting + circuit breaker adicional |
| Elevation of Privilege | Token manipulado | Firma HMAC | Considerar roles granulares y scoping |

## 9. Estrategia de Tokens (Estado Actual)
| Aspecto | Valor | Riesgo |
|---------|-------|-------|
| Algoritmo | HS256 | Compartir secreto entre servicios (único punto) |
| Expiración | 72h | Persistencia larga en caso de fuga |
| Revocación | No implementada | Tokens comprometidos válidos hasta exp |
| Rotación clave | No | Imposible invalidar conjuntos selectivos |

Recomendado: introducir tabla/JSON de claves activas + `kid` en header JWT, permitir rotación progresiva (dual-key window).

## 10. Docker/Contenedores – Recomendaciones
| Componente | Mejora | Acción |
|------------|--------|-------|
| auth-api | Non-root, multi-stage | Añadir builder + copy bin minimal |
| users-api | JVM tuning | Adoptar JDK slim base |
| todos-api | Node Alpine | Purgar devDeps en stage final |
| log-message-processor | Python slim | Usar `python:3.x-alpine` + pip --no-cache-dir |
| frontend | Build separado | Stage build + Nginx/Dist static |

## 11. Observabilidad de Seguridad (Sugerida)
Implementar métricas Prometheus:
- `auth_login_attempts_total{result="success|fail"}`
- `todos_api_requests_total{status="2xx|4xx|5xx"}`
- `circuit_breaker_state{name="users-api-cb"}` (gauge: 0 closed,1 open,2 half-open)

Log correlation:
- Generar `X-Correlation-Id` en frontera (frontend / API gateway futuro) y propagar.

## 12. Política de Secretos
| Práctica | Estado | Próximo Paso |
|----------|--------|--------------|
| `.env` fuera de control | ✅ | Asegurar `.env.example` sin valores sensibles |
| Uso de variables de entorno | ✅ | Introducir gestor central (Vault/KeyVault) |
| Rotación | ❌ | Script + schedule pipeline |
| Escopado mínimo | Parcial | Tokens por servicio (si se migra a JWKs) |

## 13. Integración con Pipelines (Acciones Concretas)
Agregar al workflow de build:
```yaml
- name: Scan image (Trivy)
  uses: aquasecurity/trivy-action@v0.20.0
  with:
    image-ref: ghcr.io/${{ github.repository_owner }}/microservice-app-auth-api:${{ github.sha }}
    format: 'table'
    exit-code: '1'
    vuln-type: 'os,library'
    severity: 'CRITICAL,HIGH'
```
(Replicar para cada servicio o usar matrix.)

## 14. Resumen Ejecutivo
El proyecto ha mejorado sustancialmente su postura de seguridad eliminando secretos hardcodeados, añadiendo validaciones, headers y circuit breaker. Las mayores brechas pendientes se concentran en: rotación/gestión de secretos, ausencia de límites de petición, ausencia de escaneo automático y falta de persistencia transaccional real. El roadmap propuesto prioriza mitigaciones de alto impacto y bajo costo para una maduración rápida.

---
Fin del documento.

