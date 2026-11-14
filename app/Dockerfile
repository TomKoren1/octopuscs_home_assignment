FROM node:24-alpine

ENV NODE_ENV=production

WORKDIR /app

# Dependencies first: code changes reuse the cached `npm ci` layer
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY server.js ./

# Set by CI to the commit SHA; declared late to keep the layers above cached
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

USER node

EXPOSE 3000

# Exec form: node is PID 1 and gets SIGTERM from `docker stop`
CMD ["node", "server.js"]
