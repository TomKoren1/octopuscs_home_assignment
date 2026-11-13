FROM node:24-alpine

# Tells Express (and npm) to run in production mode
ENV NODE_ENV=production

WORKDIR /app

# 1) Copy ONLY the dependency manifests and install.
#    This layer is cached and re-used until package*.json changes,
#    so editing server.js does not trigger a new `npm ci`.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# 2) Copy the application code (changes often -> last layer)
COPY server.js ./

# Do not run as root. The `node` user already exists in the base image.
USER node

# Documentation only: the port the app listens on inside the container
EXPOSE 3000

# Exec form: node is PID 1 and receives SIGTERM directly from `docker stop`
CMD ["node", "server.js"]
