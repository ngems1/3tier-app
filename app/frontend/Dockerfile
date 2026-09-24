# syntax=docker/dockerfile:1

# ---- build stage: reproducible install from the lockfile, then static build ----
FROM node:22-alpine AS build
WORKDIR /usr/src/app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# ---- runtime stage: unprivileged Nginx serving the static build ----
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=build /usr/src/app/build /usr/share/nginx/html
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

# Defaults for Docker Compose; ECS overrides them in the task definition.
ENV BACKEND_URL=backend:8000 \
    DNS_RESOLVER=127.0.0.11

ARG APP_VERSION=dev
LABEL org.opencontainers.image.version=${APP_VERSION}

USER 101
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
