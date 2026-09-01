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

# Migration SQL is read at runtime by the unprivileged `node` user.  Normalize
# permissions here so a restrictive checkout/umask on the deployment host
# cannot make a migration unreadable and trap the container in a restart loop.
RUN chmod -R a+rX /app/migrations \
    && chown -R node:node /app/migrations \
    && mkdir -p /app/uploads \
    && chown -R node:node /app/uploads

EXPOSE 3000

USER node

CMD ["node", "dist/index.js"]
