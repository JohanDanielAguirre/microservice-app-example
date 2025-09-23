# Frontend simplificado - sin node-sass
FROM node:12-alpine

WORKDIR /app

# Instalar git
RUN apk add --no-cache git

# Copiar package.json y modificarlo para quitar node-sass
COPY package.json ./
RUN sed -i '/"node-sass"/d' package.json && \
    sed -i '/"sass-loader"/d' package.json

# Instalar dependencias sin problemas
RUN npm install --no-audit --legacy-peer-deps --no-optional || echo "Some packages failed but continuing..."

# Copiar código
COPY . .

# Variables de entorno
ENV PORT=8080 \
    AUTH_API_ADDRESS=http://auth-api:8000 \
    TODOS_API_ADDRESS=http://todos-api:8082 \
    ZIPKIN_URL=http://zipkin:9411/api/v2/spans

EXPOSE 8080

CMD ["npm", "start"]