# Three targets (mirrors astarte/Dockerfile):
#   dev      — full install + `react-router dev` (HMR). Source bind-mounted.
#   build    — install + `pnpm build` → build/client + build/server. (intermediate)
#   runtime  — slim image, prod deps only, non-root. (default)
#
# `docker build` (no --target) gives the runtime image. The local compose
# override sets `target: dev` for hot-reload dev.
#
# pnpm comes via corepack (version pinned by package.json "packageManager").
# The esbuild build script is allow-listed in pnpm-workspace.yaml, so installs
# are non-interactive; `prepare` (panda codegen) runs during install.

# --- dev: HMR server, source bind-mounted by the compose override ---
FROM node:26-slim AS dev
WORKDIR /app
RUN npm install -g corepack@latest && corepack enable
COPY . .
RUN pnpm install --frozen-lockfile
EXPOSE 3000
# --host binds vite to 0.0.0.0 so the mapped port is reachable from the host.
CMD ["pnpm", "dev", "--host"]

# --- build: produce the production server + client bundles ---
FROM node:26-slim AS build
WORKDIR /app
RUN npm install -g corepack@latest && corepack enable
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm build

# --- runtime: slim prod image, prod deps only, no source/build tooling ---
FROM node:26-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN npm install -g corepack@latest && corepack enable
# Prod deps only; --ignore-scripts skips `prepare` (codegen, already baked into
# the build) and the esbuild build (dev-only tooling, absent from prod deps).
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --prod --frozen-lockfile --ignore-scripts
COPY --from=build /app/build ./build

# Non-root: the node:* images ship a `node` user at UID 1000.
RUN chown -R node:node /app
USER node

# Container-level healthcheck via the node stdlib (no curl). The Traefik
# loadbalancer healthcheck (compose labels) is the source of truth for routing;
# this one drives Docker / Dokploy's container status column.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

EXPOSE 3000
# Exec the server binary directly so it's PID 1 and handles SIGTERM cleanly.
CMD ["./node_modules/.bin/react-router-serve", "./build/server/index.js"]
