# Implementación de Cache Aside Pattern con Azure Redis Cache

## Resumen

Se ha implementado el patrón **Cache Aside** (también conocido como **Lazy Loading**) en los microservicios para mejorar el rendimiento y reducir la carga en las bases de datos.

## ¿Qué es Cache Aside?

Cache Aside es un patrón de caché donde:
1. **Read**: La aplicación verifica el caché primero, si no encuentra los datos (cache miss), los carga de la base de datos y los almacena en el caché
2. **Write**: La aplicación escribe directamente en la base de datos y luego invalida el caché

## Arquitectura Implementada

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │   Auth API      │    │   Todos API     │
│   (Vue.js)      │    │   (Go)          │    │   (Node.js)     │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │                      │                      │
          ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Redis Cache                           │
│              (Cache Aside Pattern)                             │
└─────────────────────────────────────────────────────────────────┘
          │                      │                      │
          │                      │                      │
          ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Users API     │    │   Memory Cache  │    │   Memory Cache  │
│   (Java/Spring) │    │   (Fallback)    │    │   (Fallback)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Servicios Modificados

### 1. Auth API (Go)
- **Archivo**: `auth-api/cache.go`
- **Patrón**: Cache de usuarios con TTL de 10 minutos
- **Clave**: `user:{username}`
- **Fallback**: Consulta directa a Users API

### 2. Todos API (Node.js)
- **Archivo**: `todos-api/cacheService.js`
- **Patrón**: Cache de listas de TODOs con TTL de 5 minutos
- **Clave**: `todos:{username}`
- **Fallback**: Memory cache local

## Configuración

### Opción 1: Azure Redis Cache (Producción)

```bash
# Ejecutar script de configuración
./configure-cache.sh

# O en PowerShell
.\configure-cache.ps1

# Cargar variables de entorno
source .env.azure
```

### Opción 2: Redis Local (Desarrollo)

```bash
# Iniciar Redis local con Docker
docker-compose -f docker-compose.cache.yml up -d

# Cargar variables de entorno locales
source .env.local
```

## Variables de Entorno

### Azure Redis Cache
```bash
REDIS_HOST=your-cache.redis.cache.windows.net
REDIS_PORT=6380
REDIS_KEY=your-primary-key
REDIS_SSL=true
```

### Redis Local
```bash
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_KEY=
REDIS_SSL=false
```

## Flujo de Datos

### Lectura (Cache Hit)
1. Cliente solicita datos
2. Servicio verifica Redis Cache
3. Datos encontrados en caché
4. Retorna datos del caché

### Lectura (Cache Miss)
1. Cliente solicita datos
2. Servicio verifica Redis Cache
3. Datos NO encontrados en caché
4. Servicio consulta fuente de datos original
5. Servicio almacena datos en caché
6. Retorna datos al cliente

### Escritura
1. Cliente envía datos para escribir
2. Servicio escribe en fuente de datos original
3. Servicio invalida caché relacionado
4. Retorna confirmación al cliente

## Beneficios Implementados

### 1. Rendimiento
- **Reducción de latencia**: Datos frecuentemente accedidos se sirven desde memoria
- **Menor carga en BD**: Menos consultas a la base de datos
- **Escalabilidad**: Redis puede manejar miles de conexiones concurrentes

### 2. Disponibilidad
- **Fallback graceful**: Si Redis falla, el sistema sigue funcionando con fuentes originales
- **Resiliencia**: El sistema no depende completamente del caché

### 3. Consistencia
- **Invalidación inmediata**: Los datos se invalidan después de escrituras
- **TTL automático**: Los datos expiran automáticamente para evitar datos obsoletos

## Monitoreo y Métricas

### Métricas Recomendadas
- **Cache Hit Rate**: Porcentaje de requests servidos desde caché
- **Cache Miss Rate**: Porcentaje de requests que requieren consulta a BD
- **Latencia promedio**: Tiempo de respuesta de operaciones
- **Uso de memoria Redis**: Monitoreo de recursos

### Comandos de Monitoreo
```bash
# Conectar a Redis
redis-cli -h your-cache.redis.cache.windows.net -p 6380 -a your-key

# Ver estadísticas
INFO stats

# Ver claves almacenadas
KEYS *

# Ver TTL de una clave
TTL user:username
```

## Configuración de Producción

### 1. Azure Redis Cache
```bash
# Crear instancia de producción
az redis create \
  --resource-group production-rg \
  --name prod-cache \
  --location eastus \
  --sku Standard \
  --vm-size C1
```

### 2. Configuración de Seguridad
- **Firewall**: Configurar reglas de IP permitidas
- **SSL**: Habilitar conexiones encriptadas
- **Autenticación**: Usar claves de acceso seguras

### 3. Configuración de Alta Disponibilidad
- **Replicación**: Configurar réplicas para failover
- **Clustering**: Para cargas de trabajo distribuidas
- **Backup**: Configurar backups automáticos

## Troubleshooting

### Problemas Comunes

1. **Conexión a Redis falla**
   - Verificar variables de entorno
   - Verificar conectividad de red
   - Verificar credenciales

2. **Datos no se almacenan en caché**
   - Verificar configuración de TTL
   - Verificar permisos de escritura
   - Verificar logs de errores

3. **Datos obsoletos en caché**
   - Verificar invalidación después de escrituras
   - Verificar configuración de TTL
   - Limpiar caché manualmente si es necesario

### Comandos de Diagnóstico
```bash
# Verificar conexión
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_KEY ping

# Ver estadísticas de memoria
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_KEY info memory

# Limpiar caché
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_KEY flushall
```

## Próximos Pasos

1. **Implementar métricas**: Agregar logging de cache hit/miss rates
2. **Configurar alertas**: Alertas para fallos de Redis
3. **Optimizar TTL**: Ajustar tiempos de expiración según patrones de uso
4. **Implementar cache warming**: Precargar datos críticos
5. **Agregar cache distribuido**: Para múltiples instancias de servicios

## Archivos Creados/Modificados

- `auth-api/cache.go` - Servicio de caché para Go
- `todos-api/cacheService.js` - Servicio de caché para Node.js
- `azure-setup.sh` - Script de configuración de Azure (Linux/Mac)
- `azure-setup.ps1` - Script de configuración de Azure (Windows)
- `configure-cache.sh` - Script de configuración completo (Linux/Mac)
- `configure-cache.ps1` - Script de configuración completo (Windows)
- `docker-compose.cache.yml` - Configuración Docker para desarrollo local
- `.env.azure` - Variables de entorno para Azure (generado automáticamente)
- `.env.local` - Variables de entorno para desarrollo local (generado automáticamente)
