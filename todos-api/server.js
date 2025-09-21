'use strict';
const express = require('express')
const bodyParser = require("body-parser")
const jwt = require('express-jwt')

const ZIPKIN_URL = process.env.ZIPKIN_URL || 'http://127.0.0.1:9411/api/v2/spans';
const {Tracer, 
  BatchRecorder,
  jsonEncoder: {JSON_V2}} = require('zipkin');
  const CLSContext = require('zipkin-context-cls');  
const {HttpLogger} = require('zipkin-transport-http');
const zipkinMiddleware = require('zipkin-instrumentation-express').expressMiddleware;

const logChannel = process.env.REDIS_CHANNEL || 'log_channel';
// Migrar a redis v4
const { createClient } = require('redis');

// Support Azure Cache for Redis via REDIS_URL or via host/port/password and TLS flag
const redisUrlEnv = process.env.REDIS_URL;
const redisHost = process.env.REDIS_HOST || 'localhost';
const redisPort = process.env.REDIS_PORT || 6379;
const redisPassword = process.env.REDIS_PASSWORD;
const redisUseTls = (process.env.REDIS_USE_TLS === 'true' || process.env.REDIS_USE_TLS === '1');

let redisUrl;
if (redisUrlEnv) {
  // If a full URL is provided, use it directly. Example: rediss://:password@mycache.redis.cache.windows.net:6380
  redisUrl = redisUrlEnv;
} else {
  const scheme = redisUseTls ? 'rediss' : 'redis';
  if (redisPassword) {
    // include password in URL (note the empty username before colon)
    redisUrl = `${scheme}://:${encodeURIComponent(redisPassword)}@${redisHost}:${redisPort}`;
  } else {
    redisUrl = `${scheme}://${redisHost}:${redisPort}`;
  }
}

const clientOptions = { url: redisUrl };
if (redisUseTls) {
  // node-redis recognizes rediss scheme; adding socket tls option helps some environments
  clientOptions.socket = { tls: true };
}
// If password provided separately, set it explicitly (createClient will accept either URL with auth or password option)
if (redisPassword && !redisUrlEnv) {
  clientOptions.password = redisPassword;
}

let redisClient = createClient(clientOptions);
redisClient.on('error', (err) => {
  console.error('Redis Client Error:', err);
});
// Conectar de forma asíncrona; no bloquea el arranque
redisClient.connect().then(() => {
  console.log('Connected to Redis at', redisUrl);
}).catch((err) => {
  console.error('Failed to connect to Redis:', err);
  // Keep redisClient instance but it will not be open; controllers will fallback to memory-cache
});

const port = process.env.TODO_API_PORT || 8082
const jwtSecret = process.env.JWT_SECRET
if (!jwtSecret) {
  console.error('JWT_SECRET environment variable is required')
  process.exit(1)
}

const app = express()

// tracing
const ctxImpl = new CLSContext('zipkin');
const recorder = new  BatchRecorder({
  logger: new HttpLogger({
    endpoint: ZIPKIN_URL,
    jsonEncoder: JSON_V2
  })
});
const localServiceName = 'todos-api';
const tracer = new Tracer({ctxImpl, recorder, localServiceName});


// Security headers
app.use(function(req, res, next) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  next();
});

// Configurar express-jwt para HS256 y mantener req.user
app.use(jwt({ secret: jwtSecret, algorithms: ['HS256'], requestProperty: 'user' }))
app.use(zipkinMiddleware({tracer}));
app.use(function (err, req, res, _next) {
  if (err.name === 'UnauthorizedError') {
    res.status(401).json({ error: 'Invalid token' })
  } else {
    console.error('Unexpected error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
})
app.use(bodyParser.urlencoded({ extended: false }))
app.use(bodyParser.json())

const routes = require('./routes')
routes(app, {tracer, redisClient, logChannel})

app.listen(port, function () {
  console.log('todo list RESTful API server started on: ' + port)
})
