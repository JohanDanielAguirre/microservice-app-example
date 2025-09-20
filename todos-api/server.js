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
const redisClient = require("redis").createClient({
  host: process.env.REDIS_HOST || 'localhost',
  port: process.env.REDIS_PORT || 6379,
  retry_strategy: function (options) {
      if (options.error && options.error.code === 'ECONNREFUSED') {
          return new Error('The server refused the connection');
      }
      if (options.total_retry_time > 1000 * 60 * 60) {
          return new Error('Retry time exhausted');
      }
      if (options.attempt > 10) {
          console.log('reattemtping to connect to redis, attempt #' + options.attempt)
          return undefined;
      }
      return Math.min(options.attempt * 100, 2000);
  }        
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

app.use(jwt({ secret: jwtSecret }))
app.use(zipkinMiddleware({tracer}));
app.use(function (err, req, res, next) {
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
