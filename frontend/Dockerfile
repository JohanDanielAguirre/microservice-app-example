# Frontend (Vue 2 dev server)
# Usamos Node 12 para compatibilidad con node-sass y toolchain antigua
FROM node:12-alpine
WORKDIR /app

# Instalar dependencias
COPY package.json package-lock.json* ./
RUN npm install --quiet

# Copiar código
COPY . .

ENV PORT=8080 \
    AUTH_API_ADDRESS=http://auth-api:8000 \
    TODOS_API_ADDRESS=http://todos-api:8082 \
    ZIPKIN_URL=http://zipkin:9411/api/v2/spans

EXPOSE 8080
CMD ["npm", "start"]

