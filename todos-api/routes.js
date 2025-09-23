'use strict';
const TodoController = require('./todoController');
module.exports = function (app, {tracer, redisClient, logChannel}) {
  const todoController = new TodoController({tracer, redisClient, logChannel});
  
  // Ruta raíz para evitar "Cannot GET /" y "Method Not Allowed"
  app.get('/', function(req, res) {
    res.json({
      service: 'todos-api',
      message: 'Cache-Aside Pattern Implementation',
      endpoints: [
        'GET /todos - List all todos (Cache-Aside pattern)',
        'POST /todos - Create new todo',
        'DELETE /todos/:taskId - Delete todo'
      ],
      cache: 'Redis with memory-cache fallback',
      status: 'running'
    });
  });

  app.route('/todos')
    .get(function(req,resp) {return todoController.list(req,resp)})
    .post(function(req,resp) {return todoController.create(req,resp)});

  app.route('/todos/:taskId')
    .delete(function(req,resp) {return todoController.delete(req,resp)});
};