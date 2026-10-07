# syntax=docker/dockerfile:1

ARG BUN_VERSION=1.4.2
ARG CADDY_VERSION=2

# ---------------------------------------------------------------------------
# Source: the conex repository at CONEX_VERSION (branch, tag or commit).
# Override with a local checkout via `--build-context conex-src=../conex`.
# ---------------------------------------------------------------------------
FROM scratch AS conex-src
ARG CONEX_REPO=https://github.com/serkonda7/conex.git
ARG CONEX_VERSION=main
ADD ${CONEX_REPO}#${CONEX_VERSION} /

# ---------------------------------------------------------------------------
# Builder: install workspace deps and build server bundle + client assets.
# ---------------------------------------------------------------------------
FROM oven/bun:${BUN_VERSION} AS builder
WORKDIR /src
COPY --from=conex-src package.json bun.lock ./
COPY --from=conex-src server/package.json server/
COPY --from=conex-src client/package.json client/
COPY --from=conex-src shared/package.json shared/
COPY --from=conex-src plugins/agfeo-ldap/package.json plugins/agfeo-ldap/
RUN --mount=type=cache,target=/root/.bun/install/cache \
	bun install --frozen-lockfile

# Excludes matter for local build contexts (host deps, build output, app data).
COPY --from=conex-src \
	--exclude=**/node_modules --exclude=**/dist --exclude=**/data \
	--exclude=**/.turbo --exclude=test-results --exclude=.git \
	. .
RUN bun run --cwd server build \
	&& bun run --cwd client build \
	&& bun run --cwd plugins/agfeo-ldap build

# ---------------------------------------------------------------------------
# conex: API server (bun, Postgres via CONEX_DATABASE_URL). Listens on :3000.
# ---------------------------------------------------------------------------
FROM oven/bun:${BUN_VERSION}-slim AS conex
ARG CONEX_VERSION=main

LABEL org.opencontainers.image.title="conex" \
	org.opencontainers.image.description="conex API server" \
	org.opencontainers.image.source="https://github.com/serkonda7/conex" \
	org.opencontainers.image.licenses="MPL-2.0" \
	org.opencontainers.image.version="${CONEX_VERSION}"

WORKDIR /opt/conex
COPY --from=builder /src/server/dist/ ./dist/
COPY --from=builder /src/server/drizzle/ ./drizzle/
COPY docker/healthcheck.ts /opt/conex/healthcheck.ts

RUN mkdir -p /opt/conex/data \
	&& chown bun:bun /opt/conex/data

# Mount the server config here (see config.toml.example).
ENV CONEX_CONFIG_PATH=/etc/conex/config.toml
ENV CONEX_SERVER_PORT=3000
USER bun
VOLUME ["/opt/conex/data"]
EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
	CMD ["bun", "/opt/conex/healthcheck.ts"]

CMD ["bun", "dist/index.js"]

# ---------------------------------------------------------------------------
# conex-web: Caddy serving the SPA over HTTPS and proxying /api to the API.
# Listens on :80 (redirect) and :443. Certificates are kept in the /data volume.
# ---------------------------------------------------------------------------
FROM caddy:${CADDY_VERSION}-alpine AS conex-web
ARG CONEX_VERSION=main

LABEL org.opencontainers.image.title="conex-web" \
	org.opencontainers.image.description="conex web UI (Caddy)" \
	org.opencontainers.image.source="https://github.com/serkonda7/conex" \
	org.opencontainers.image.licenses="MPL-2.0" \
	org.opencontainers.image.version="${CONEX_VERSION}"

COPY docker/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /src/client/dist/ /srv/

ENV CONEX_API_UPSTREAM=conex:3000
ENV CONEX_HOST=localhost
EXPOSE 80 443 443/udp

# ---------------------------------------------------------------------------
# agfeo-ldap: optional LDAP contact directory for the AGFEO Dashboard. Listens
# on :1389, as the bun user cannot bind ports below 1024.
# ---------------------------------------------------------------------------
FROM oven/bun:${BUN_VERSION}-slim AS agfeo-ldap
ARG CONEX_VERSION=main

LABEL org.opencontainers.image.title="conex-agfeo-ldap" \
	org.opencontainers.image.description="conex contact directory over LDAP for the AGFEO Dashboard" \
	org.opencontainers.image.source="https://github.com/serkonda7/conex" \
	org.opencontainers.image.licenses="MPL-2.0" \
	org.opencontainers.image.version="${CONEX_VERSION}"

WORKDIR /opt/agfeo-ldap
COPY --from=builder /src/plugins/agfeo-ldap/dist/ ./dist/

ENV AGFEO_LDAP_CONEX_URL=http://conex:3000
ENV AGFEO_LDAP_PORT=1389
USER bun
EXPOSE 1389

CMD ["bun", "dist/index.js"]
