# Circuit Breaker – Implementación y Guía

Este documento describe cómo está implementado el patrón **Circuit Breaker** en este repositorio, qué variables lo configuran, cómo probarlo y recomendaciones de mejora.

## 1. Objetivo del Circuit Breaker
El patrón Circuit Breaker evita que un servicio saturado o caído cause bloqueo o cascada de fallos en el resto del sistema. Cuando se detectan fallos consecutivos, el breaker “abre” el circuito y rechaza llamadas inmediatamente hasta que se cumpla un periodo de recuperación.

Estados típicos:
- **Closed**: Flujo normal, los errores incrementan contadores.
- **Open**: Se alcanzó el umbral de fallos, se rechazan nuevas llamadas directamente (fail-fast).
- **Half-Open**: Periodo de prueba: se permite un número limitado de llamadas para ver si el servicio objetivo se recuperó.

## 2. Dónde está implementado
### 2.1 Auth API (Go)
Archivos relevantes:
- `auth-api/main.go`
- `auth-api/user.go`

Se usa la librería [`github.com/sony/gobreaker`](https://github.com/sony/gobreaker) para envolver las llamadas de `Auth API` hacia `Users API` durante la autenticación.

Flujo simplificado de login:
1. `/login` recibe usuario/contraseña.
2. `UserService.Login` → `getUser`.
3. `getUser` ejecuta request HTTP a `Users API` dentro de `Breaker.Execute` (si está configurado).
4. Ante fallos consecutivos ≥ umbral → estado Open → se devuelven errores `503 Service Unavailable` personalizados.

### 2.2 Log Message Processor (Python)
Archivo: `log-message-processor/main.py`

Se usa la librería [`pybreaker`](https://pypi.org/project/pybreaker/) para proteger las llamadas HTTP de envío de spans a Zipkin. Si Zipkin está lento o caído, el breaker evita que el loop de consumo de Redis se bloquee.

## 3. Variables de entorno (Go – Auth API)
| Variable | Descripción | Valor por defecto (si vacío) |
|----------|-------------|-------------------------------|
| `CB_ENABLED` | Activa el breaker (`1` / `true`) | Desactivado si vacío |
| `CB_TIMEOUT_MS` | (Histórico) Timeout base; reemplazado por `CB_RESET_TIMEOUT_MS` en esta implementación | 2000 |
| `CB_RESET_TIMEOUT_MS` | Tiempo (ms) antes de pasar de Open a Half-Open | 10000 |
| `CB_ERROR_THRESHOLD` | Fallos consecutivos para abrir | 5 |
| `CB_REQUEST_TIMEOUT_MS` | Timeout por request HTTP al Users API | 1500 |

Notas:
- El código prioriza `CB_RESET_TIMEOUT_MS` asignándolo a `Settings.Timeout`.
- `MaxRequests=1` en Half-Open permite una única “sonda” antes de decidir cerrar u abrir de nuevo.

## 4. Variables de entorno (Python – Log Processor)
| Variable | Descripción | Default |
|----------|-------------|---------|
| `CB_ZIPKIN_FAIL_MAX` | Fallos antes de abrir | 5 |
| `CB_ZIPKIN_RESET_TIMEOUT` | Segundos antes de intento Half-Open | 30 |
| `CB_ZIPKIN_TIMEOUT` | Timeout segundos request Zipkin | 2.0 |

## 5. Manejo de errores y códigos HTTP
Auth API convierte:
- `gobreaker.ErrOpenState` / `gobreaker.ErrTooManyRequests` ⇒ `503 users service unavailable (circuit open)`
- `context.DeadlineExceeded` ⇒ `503 users service timeout`
- Errores de red (`net.Error`) ⇒ `503 users service network error`
- Credenciales inválidas ⇒ `401 username or password is invalid`

Python Log Processor:
- No detiene el flujo de mensajes; si el breaker está abierto, se omite el envío a Zipkin y se imprime el log localmente.

## 6. Cómo forzar y observar el Circuit Breaker (Auth API)
1. Arranca el stack normalmente (`docker compose up -d`).
2. Edita la variable `USERS_API_ADDRESS` del contenedor `auth-api` para apuntar a un host inexistente (ej: `http://users-api-broken:9999`). Puedes:
   ```bash
   docker compose stop auth-api
   docker compose run -e USERS_API_ADDRESS=http://users-api-broken:9999 -e CB_ENABLED=true -e JWT_SECRET=.... auth-api
   ```
3. Realiza múltiples intentos de login (≥ umbral configurado):
   ```bash
   for i in {1..6}; do curl -s -o /dev/null -w "%{http_code}\n" \
     -X POST http://127.0.0.1:8000/login \
     -H 'Content-Type: application/json' \
     -d '{"username":"admin","password":"admin"}'; done
   ```
4. Verás algunas respuestas 500/503 hasta que el breaker abra. Tras abrir, las respuestas se estabilizan en 503 inmediato.
5. Espera `CB_RESET_TIMEOUT_MS` ms y prueba de nuevo: se permitirá 1 request (Half-Open). Si falla, vuelve a Open; si tiene éxito, vuelve a Closed.

Logs esperados:
```
circuit-breaker 'users-api-cb' state change: closed -> open
circuit-breaker 'users-api-cb' state change: open -> half-open
circuit-breaker 'users-api-cb' state change: half-open -> open (si vuelve a fallar)
```

## 7. Estrategia Interna (Auth API)
- `ReadyToTrip`: función que abre el circuito cuando `ConsecutiveFailures >= CB_ERROR_THRESHOLD`.
- Sin ventana deslizante (no se usa `Interval` > 0), se cuenta desde último cambio de estado.
- `RequestTimeout` corta requests lentos y ayuda a acumular fallos controlados.

## 8. Comparación rápida de implementaciones
| Aspecto | Auth API (Go) | Log Processor (Python) |
|---------|---------------|------------------------|
| Librería | gobreaker | pybreaker |
| Protección | Llamadas a Users API | Envío spans Zipkin |
| Tipo de fallo principal | Red / timeout / servicio caído | Telemetría fallida / Zipkin caído |
| Efecto en flujo | Devuelve 503 al cliente | No interrumpe consumo de mensajes |
| Half-Open | 1 request (MaxRequests=1) | Manejada internamente por pybreaker |

## 9. Buenas prácticas y mejoras recomendadas
1. Métricas: exponer contadores (abiertos, éxitos, fallos) vía endpoint `/metrics` (Prometheus).
2. Logging estructurado: añadir campos JSON para estado y latencia.
3. Fallback: cachear perfil mínimo (para Auth API) si Users API está caído (trade-off seguridad vs disponibilidad).
4. Ajuste dinámico: usar config centralizada (Consul, etcd) para cambiar umbrales sin redeploy.
5. Alarmas: integrar con sistema de alertas (abrir circuito > N minutos ⇒ alerta).
6. Distribución: si hay múltiples réplicas, cada instancia mantiene su propio estado; evaluar breaker “compartido” (backoff coordinado) si necesario.

## 10. Ejemplo de configuración productiva sugerida (Auth API)
| Escenario | CB_ERROR_THRESHOLD | CB_REQUEST_TIMEOUT_MS | CB_RESET_TIMEOUT_MS |
|-----------|--------------------|-----------------------|---------------------|
| Dev local lento | 5 | 2000 | 5000 |
| Producción normal | 5–10 | 800–1200 | 15000 |
| Alta latencia externa | 8–12 | 1500 | 20000 |

Ajustar tras observar p95/p99 de Users API.

## 11. Test rápido automatizable (pseudo-shell)
```bash
# 1) Éxito normal
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://127.0.0.1:8000/login \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}'

# 2) Forzar fallo cambiando destino (falla DNS)
export USERS_API_ADDRESS=http://bad-host:9999
# (Reiniciar auth-api con esa variable) y repetir n veces hasta 503 breaker
```

## 12. Señales de tuning
| Problema | Observación | Ajuste |
|----------|------------|--------|
| Abre demasiado pronto | Fallos intermitentes abren el breaker | Incrementar `CB_ERROR_THRESHOLD` |
| Recupera muy lento | Servicio sano pero se mantienen 503 | Reducir `CB_RESET_TIMEOUT_MS` |
| No detecta degradación | Latencias muy altas sin cortar | Reducir `CB_REQUEST_TIMEOUT_MS` |
| Demasiados falsos negativos | Timeouts por threshold muy bajo | Aumentar `CB_REQUEST_TIMEOUT_MS` |

## 13. Extensiones futuras
- Integrar con librerías de resiliencia más amplias (p.ej. `resilience4j` en otros servicios Java si se migra lógica).
- Añadir Bulkhead (aislar pools HTTP) + Retry con jitter pre-circuit.
- Telemetría: spans dedicados para estados de breaker.
- Health endpoint que incluya estado del breaker.

## 14. Resumen
El Circuit Breaker protege dependencias críticas (Users API y Zipkin) para mantener la disponibilidad global y evitar cascada de fallos. Se configuró mediante variables de entorno, con umbral de fallos consecutivos y timeout de reset. Recomendado complementar con métricas, alertas y fallback controlado.

---
Fin del documento.

