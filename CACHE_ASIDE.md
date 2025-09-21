# Patrón Cache-Aside: Implementación y Uso en esta App

Este documento explica brevemente el patrón Cache-Aside (también conocido como lazy-loading), cómo está aplicado en este repositorio y cómo probarlo en ejecución.

## 1) ¿Qué es Cache-Aside?

- El patrón Cache-Aside propone que la aplicación intente leer primero desde caché y, si no encuentra los datos (cache miss), los **recupere** desde la fuente de verdad (DB/servicio), **los guarde en caché** y **devuelva** al cliente.
- En escrituras, lo normal es **actualizar la base de datos** y luego **invalidar** (o actualizar) la entrada en caché correspondiente para mantener coherencia.

Beneficios:
- Menor latencia en lecturas repetidas.
- Reduce carga a la base de datos/servicio backend.

Riesgos a gestionar:
- Caducidad (TTL) e invalidación.
- Coherencia entre caché y fuente de verdad.
- Cache stampede, warm-ups, multi-instancia, etc.

---

## 2) ¿Dónde se implementa en esta app?

En el microservicio `todos-api` (Node.js), la lógica de TODOs utiliza **caché en memoria** mediante la librería `memory-cache` para cada usuario. Esto es una versión mínima del patrón cache-aside:

- Archivo relevante: `todos-api/todoController.js`
- Clave de caché: el `username` del usuario autenticado.
- Valor almacenado: estructura `{ items: {id -> todo}, lastInsertedID: number }`.

Funciones clave:
- `_getTodoData(userID)`: 
  - Intenta leer desde caché (`memory-cache`).
  - Si no existe, construye un conjunto inicial de TODOs (semilla), lo guarda en caché y lo devuelve.
  - Esto implementa el comportamiento "load-on-miss" del cache-aside.
- `_setTodoData(userID, data)`: 
  - Actualiza la entrada del caché tras crear o borrar TODOs.

Además, las operaciones están protegidas por un mutex simple para ordenar accesos concurrentes en memoria y evitar condiciones de carrera durante lecturas/escrituras.

Notas importantes de esta implementación:
- Aquí el caché es **la única** capa de datos de TODOs (no hay DB). Se usa a modo demostrativo del patrón. En un diseño real, el **origen de verdad** sería una base de datos y la caché sólo un acelerador.
- El caché es **local al proceso** (memoria del contenedor/instancia). Si escalas múltiples instancias de `todos-api`, cada una tendrá su propio caché y no se sincronizarán entre sí.

---

## 3) Flujo de lectura y escritura (resumen)

Lectura `GET /todos` (por usuario):
1. Se obtiene el `username` del token JWT.
2. Se llama a `_getTodoData(username)`
   - Hit: devuelve los datos desde memoria.
   - Miss: crea datos semilla, guarda en caché y devuelve.

Creación `POST /todos`:
1. Valida entrada (`content` requerido).
2. Obtiene datos del usuario desde caché (`_getTodoData`).
3. Inserta el nuevo TODO y **actualiza el caché** (`_setTodoData`).

Borrado `DELETE /todos/:id`:
1. Obtiene datos del usuario desde caché.
2. Borra el item y **actualiza el caché** (`_setTodoData`).

---

## 4) Cómo ejecutarlo y observar el caché en acción

Puedes levantar todo el sistema con Docker Compose. En la raíz del repo:

```bat
copy .env.example .env
REM Edita .env y pon un JWT_SECRET fuerte (mínimo 32 caracteres)

docker compose up -d --build
```

Servicios expuestos:
- frontend: http://127.0.0.1:8080
- auth-api: http://127.0.0.1:8000 (login)
- todos-api: http://127.0.0.1:8082 (CRUD TODOs)

Prueba rápida (Windows cmd):

1) Obtén un token JWT
```bat
curl -X POST http://127.0.0.1:8000/login ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"admin\",\"password\":\"admin\"}"
```
Copia el `accessToken` del JSON de respuesta.

2) Lista tus TODOs (primer GET calentará el caché para tu usuario)
```bat
set TOKEN=PEGA_AQUI_TU_TOKEN
curl -H "Authorization: Bearer %TOKEN%" http://127.0.0.1:8082/todos
```
Deberías ver 3 TODOs de ejemplo. Esta respuesta queda en **memoria** para ese contenedor y usuario.

3) Crea un TODO y vuelve a listar
```bat
curl -X POST -H "Authorization: Bearer %TOKEN%" ^
  -H "Content-Type: application/json" ^
  -d "{\"content\":\"tarea desde curl\"}" ^
  http://127.0.0.1:8082/todos

curl -H "Authorization: Bearer %TOKEN%" http://127.0.0.1:8082/todos
```
Verás el nuevo elemento en la lista: ha sido **persistido en caché** (memoria) y devuelto en la siguiente lectura (cache hit).

4) Reinicia el contenedor `todos-api` y vuelve a listar
```bat
docker compose restart todos-api
curl -H "Authorization: Bearer %TOKEN%" http://127.0.0.1:8082/todos
```
Como el caché es **en memoria del proceso**, al reiniciar se pierde y la primera petición volverá a crear datos semilla (cache miss + warm).

---

## 5) Recomendaciones para producción

La implementación actual es deliberadamente simple (caché en memoria y única fuente de datos). Para un cache-aside "real" con DB, considera:

- Fuente de verdad (DB)
  - En lecturas: DB sólo cuando no esté la entrada en caché.
  - En escrituras: primero **DB**, luego **invalidar/actualizar caché**.

- Caché distribuida
  - Usa Redis/Memcached como **caché externo** para compartir datos entre réplicas.
  - Claves sugeridas: `todos:user:<username>`
  - TTL recomendado (ej.: 60–300s), según necesidades de frescura.

- Estrategias de coherencia
  - Post-escritura: invalidar la clave del usuario (o actualizarla) para evitar datos obsoletos.
  - Evitar stampedes: usar locking o randomizar TTL.

- Observabilidad
  - Mide ratio de hit/miss del caché.
  - Expón métricas para tuning de TTL y tamaño del caché.

---

## 6) (Opcional) Migrar la caché a Redis para TODOs

Si quieres que múltiples instancias compartan la misma caché y que sobreviva reinicios del proceso, puedes migrar el caché a Redis:

- Concepto:
  - En `_getTodoData(userID)`: intenta `GET todos:user:<userID>` en Redis. Si existe, parsea y devuelve. Si no existe, construye semilla, `SET` en Redis (con `EX` para TTL) y devuelve.
  - En `_setTodoData(userID, data)`: `SET todos:user:<userID>` con TTL.
  - En `DELETE`/`CREATE`: después de persistir en DB (cuando exista), **actualiza o invalida** la clave de Redis.

- Consideraciones:
  - Añade TTL: evita que la caché se llene con claves huérfanas y favorece refresco periódico.
  - Manejo de errores: si Redis está caído, **degrada** a memoria o a DB.

### 6.1) Conexión a Azure Cache for Redis

Para que `todos-api` use Azure Cache for Redis (instancia administrada), la aplicación acepta las siguientes variables de entorno:

- `REDIS_URL` (recomendado): URL completa de conexión. Ejemplo (Azure usa TLS y puerto 6380):
  - `rediss://:SECRETPASSWORD@<your-cache-name>.redis.cache.windows.net:6380`
- `REDIS_PASSWORD`: contraseña (si no usas `REDIS_URL`, puedes proveer host/port + password)
- `REDIS_HOST` y `REDIS_PORT`: si prefieres construir la URL desde partes (fallback local: `localhost:6379`)
- `REDIS_USE_TLS`: `true` si la conexión requiere TLS (Azure lo requiere). Alternativamente usa `rediss://` en `REDIS_URL`.
- `REDIS_CHANNEL`: canal para `publish` de logs/operaciones (por defecto `log_channel`).
- `TODO_CACHE_TTL`: TTL en segundos para las claves de TODOs (por defecto `300`).

Ejemplo (Windows cmd.exe):

```bat
set REDIS_URL=rediss://:MiPasswordSecreta@mi-cache.redis.cache.windows.net:6380
set REDIS_USE_TLS=true
set TODO_CACHE_TTL=300
set JWT_SECRET=una_clave_jwt_muy_fuerte_con_al_menos_32_chars
node server.js
```

Comportamiento implementado en el código:
- Si `redisClient` está disponible y conectado, `todos-api` usará Redis para GET/SET de la clave `todos:user:<username>` con TTL (cache-aside).
- Si Redis no está disponible o la operación falla, la aplicación degrada a una caché en memoria local (`memory-cache`). Esto preserva la disponibilidad pero no garantiza coherencia entre réplicas.

Notas de producción con Azure:
- Asegúrate de permitir el acceso desde la IP/entorno donde esté corriendo tu servicio (vNet/firewall de Azure Cache for Redis).
- Usa TLS (Azure lo requiere) y el puerto 6380.
- Configura réplicas y políticas de expiración según tus necesidades de coherencia.

---

## 6.2) Cambio en docker-compose para pruebas locales (host `redis`)

Para facilitar pruebas locales con Docker Compose he añadido una configuración en `docker-compose.yml` que fuerza a los servicios a conectarse al servicio `redis` por su nombre de host dentro de la red de Compose. En concreto, en los servicios `todos-api` y `log-message-processor` se añadió:

- `REDIS_URL=redis://redis:6379`
- `REDIS_HOST=redis`
- `REDIS_PORT=6379`

Por qué se hizo esto:
- Dentro de la red de Docker Compose el nombre del servicio (`redis`) se resuelve como hostname. De este modo el cliente Redis del contenedor `todos-api` intentará conectar a `redis:6379` en la red interna, en lugar de `localhost` o `127.0.0.1` del propio contenedor o del host.
- Esto evita errores típicos como `ECONNREFUSED` cuando la aplicación intenta conectar a `127.0.0.1:6379` (la interfaz local del contenedor) en lugar de al contenedor Redis real.

Notas operativas:
- Si ya tienes un Redis ejecutándose en el host y hay conflicto en el puerto 6379, quita el mapeo de puertos `6379:6379` del servicio `redis` en `docker-compose.yml` o cámbialo por otro puerto en el host.
- En entornos de producción en la nube (p. ej. Azure) en lugar de `redis://redis:6379` usarás `rediss://...` con TLS y la contraseña correspondiente; esta sección es sólo para pruebas locales con Docker Compose.

---

## 7) Resumen

- `todos-api` demuestra el patrón **Cache-Aside** con una caché en memoria por usuario.
- Lecturas: se sirven desde caché una vez calentado; en miss, se crea y se guarda.
- Escrituras: actualizan la estructura en caché inmediatamente.
- Para producción: usa DB como fuente de verdad, añade Redis/Memcached como caché distribuida, TTLs, invalidación tras escrituras y métricas.
