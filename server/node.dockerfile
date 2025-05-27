# Stage 1: Build dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 2: Copy source
FROM node:20-alpine AS app
WORKDIR /app

ENV NODE_ENV=production

# Copy only needed files
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Expose the port the app runs on
EXPOSE 5555

CMD ["node", "server.js"]