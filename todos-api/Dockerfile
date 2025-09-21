# TODOs API (Node.js)
FROM node:18-alpine
WORKDIR /app

# Instalar dependencias
COPY package.json package-lock.json* ./
RUN npm install --quiet

# Copiar código
COPY . .

ENV TODO_API_PORT=8082 \
    REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_CHANNEL=log_channel

EXPOSE 8082
CMD ["npm", "start"]

