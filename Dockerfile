# --- Estagio de build: compila o TypeScript ---
FROM node:26-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# --- Estagio de dependencias: apenas o que roda em producao ---
FROM node:26-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# --- Estagio final: apenas o necessario para executar ---
FROM node:26-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Atualiza os pacotes do sistema e remove o npm da imagem de execucao. O
# container so precisa do runtime do Node para rodar o processo, e um gerenciador
# de pacotes em producao e superficie de ataque sem contrapartida.
RUN apk --no-cache upgrade \
  && rm -rf /usr/local/lib/node_modules/npm \
  /usr/local/bin/npm \
  /usr/local/bin/npx

COPY package.json ./
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

USER node

EXPOSE 3000

# Sonda interna do container: o orquestrador so considera a instancia saudavel
# quando o proprio processo responde no /health.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('node:http').get('http://127.0.0.1:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "dist/server.js"]
