# Multi-stage build for Abu 3meer Production Backend
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json tsconfig.json ./
RUN npm ci

COPY src ./src
RUN npm run build

# Production runtime stage
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

COPY package*.json ./
RUN npm ci --only=production

COPY --from=builder /app/dist ./dist
COPY migrations ./migrations

RUN mkdir -p /app/uploads && chown -R node:node /app/uploads

EXPOSE 3000

USER node

CMD ["node", "dist/index.js"]
