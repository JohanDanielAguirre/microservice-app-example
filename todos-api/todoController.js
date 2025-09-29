'use strict';
const cache = require('memory-cache');

// Simple mutex implementation for concurrency safety
class Mutex {
    constructor() {
        this.locked = false;
        this.queue = [];
    }

    async lock() {
        return new Promise((resolve) => {
            if (!this.locked) {
                this.locked = true;
                resolve();
            } else {
                this.queue.push(resolve);
            }
        });
    }

    unlock() {
        if (this.queue.length > 0) {
            const next = this.queue.shift();
            next();
        } else {
            this.locked = false;
        }
    }
}

const OPERATION_CREATE = 'CREATE',
      OPERATION_DELETE = 'DELETE';

// TTL en segundos para claves en Redis (configurable)
const CACHE_TTL = parseInt(process.env.TODO_CACHE_TTL || '300', 10);

class TodoController {
    constructor({redisClient, logChannel}) {
        this._redisClient = redisClient;
        this._logChannel = logChannel;
        this._mutex = new Mutex();
    }

    // TODO: these methods are not concurrent-safe - is finish i just need to someone check it out and test it fully
    async list (req, res) {
        try {
            await this._mutex.lock();
            const data = await this._getTodoData(req.user.username);
            res.json(data.items);
        } catch (error) {
            console.error('Error in list operation:', error);
            res.status(500).json({ error: 'Internal server error' });
        } finally {
            this._mutex.unlock();
        }
    }

    async create (req, res) {
        // TODO: must be transactional and protected for concurrent access, but
        // the purpose of the whole example app it's enough - is finish i just need to someone check it out and test it fully
        try {
            await this._mutex.lock();
            
            // Validate input
            if (!req.body.content || typeof req.body.content !== 'string') {
                return res.status(400).json({ error: 'Content is required and must be a string' });
            }

            const data = await this._getTodoData(req.user.username);
            const todo = {
                content: req.body.content.trim(),
                id: data.lastInsertedID
            };
            
            data.items[data.lastInsertedID] = todo;
            data.lastInsertedID++;
            await this._setTodoData(req.user.username, data);

            this._logOperation(OPERATION_CREATE, req.user.username, todo.id);

            res.json(todo);
        } catch (error) {
            console.error('Error in create operation:', error);
            res.status(500).json({ error: 'Internal server error' });
        } finally {
            this._mutex.unlock();
        }
    }

    async delete (req, res) {
        try {
            await this._mutex.lock();
            
            const data = await this._getTodoData(req.user.username);
            const id = req.params.taskId;
            
            // Validate that the todo exists
            if (!data.items[id]) {
                return res.status(404).json({ error: 'Todo not found' });
            }
            
            delete data.items[id];
            await this._setTodoData(req.user.username, data);

            this._logOperation(OPERATION_DELETE, req.user.username, id);

            res.status(204).send();
        } catch (error) {
            console.error('Error in delete operation:', error);
            res.status(500).json({ error: 'Internal server error' });
        } finally {
            this._mutex.unlock();
        }
    }

    _logOperation (opName, username, todoId) {
        const payload = JSON.stringify({
            opName: opName,
            username: username,
            todoId: todoId,
            ts: Date.now()
        });
        if (this._redisClient && this._redisClient.publish && this._redisClient.isOpen) {
            const pub = this._redisClient.publish(this._logChannel, payload);
            if (pub && typeof pub.then === 'function') {
                pub.catch((err) => console.error('Redis publish error:', err));
            }
        } else {
            // Redis not available - no-op
        }
    }

    // Intenta Redis si está disponible (compatible con Azure Cache for Redis). Si no, cae a memory-cache.
    async _getTodoData (userID) {
        // Si Redis está activo y conectado, intentar GET
        try {
            if (this._redisClient && this._redisClient.isOpen) {
                const key = `todos:user:${userID}`;
                const raw = await this._redisClient.get(key);
                if (raw) {
                    try {
                        return JSON.parse(raw);
                    } catch (e) {
                        console.error('Failed to parse cached JSON from Redis for', key, e);
                        // continuar a fallback
                    }
                }
                // No existe en Redis: crear semilla y setear en Redis con TTL
                const data = {
                    items: {
                        '1': {
                            id: 1,
                            content: "Create new todo",
                        },
                        '2': {
                            id: 2,
                            content: "Update me",
                        },
                        '3': {
                            id: 3,
                            content: "Delete example ones",
                        }
                    },
                    // Comenzar en 4 para evitar duplicar el id 3 existente
                    lastInsertedID: 4
                };
                try {
                    await this._redisClient.setEx(key, CACHE_TTL, JSON.stringify(data));
                } catch (e) {
                    console.error('Failed to set key in Redis, falling back to memory-cache:', e);
                    cache.put(userID, data);
                }
                return data;
            }
        } catch (err) {
            console.error('Error while interacting with Redis in _getTodoData:', err);
            // continuar a fallback
        }

        // Fallback: cache en memoria local
        var data = cache.get(userID)
        if (data == null) {
            data = {
                items: {
                    '1': {
                        id: 1,
                        content: "Create new todo",
                    },
                    '2': {
                        id: 2,
                        content: "Update me",
                    },
                    '3': {
                        id: 3,
                        content: "Delete example ones",
                    }
                },
                // Comenzar en 4 para evitar duplicar el id 3 existente
                lastInsertedID: 4
            }

            this._setTodoData(userID, data)
        }
        return data
    }

    async _setTodoData (userID, data) {
        // Si Redis está activo y conectado, intentar SET con TTL
        try {
            if (this._redisClient && this._redisClient.isOpen) {
                const key = `todos:user:${userID}`;
                await this._redisClient.setEx(key, CACHE_TTL, JSON.stringify(data));
                return;
            }
        } catch (err) {
            console.error('Error while setting data in Redis:', err);
            // caer al fallback
        }

        // Fallback: cache en memoria local
        cache.put(userID, data)
    }
}

module.exports = TodoController