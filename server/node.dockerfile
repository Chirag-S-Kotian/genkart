# Stage 1: Build dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 2: Copy source
FROM node:20-alpine AS app
WORKDIR /app

# Copy only needed files
COPY --from=deps /app/node_modules ./node_modules
COPY . .

EXPOSE 3000
CMD ["node", "server.js"]