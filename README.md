# conex-docker
Docker deployment for [conex](https://github.com/serkonda7/conex).

It builds the `main` branch by default. Two images come from one
`Dockerfile`, and compose adds a stock Postgres:

| Service     | Contents                                              | Port |
| ----------- | ----------------------------------------------------- | ---- |
| `conex`     | bun API server, state in the `/opt/conex/data` volume | 3000 |
| `conex-web` | Caddy serving the UI over HTTPS, proxying `/api/*`    | 443  |
| `postgres`  | `postgres:17-alpine`, the conex database              | 5432 |

The optional `agfeo-ldap` service serves the conex contacts over LDAP for the
AGFEO Dashboard (see [AGFEO Dashboard](#agfeo-dashboard-optional)).


## Quickstart
```sh
git clone <this repo> conex-docker
cd conex-docker
cp docker-compose.override.yml.example docker-compose.override.yml
sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env.example > .env
sed "s/^appKey = .*/appKey = \"$(openssl rand -hex 48)\"/" config.toml.example > config.toml
docker compose up -d --build
```

Open <https://localhost> and create the admin account in the first-run
dialog. The browser warns about the certificate until you trust Caddy's local
CA (see [HTTPS](#https)).


## Configuration
- `config.toml`: the server config, mounted read-only into `conex`. Start from
  `config.toml.example`. conex refuses to start without an `appKey` of at
  least 32 characters.
- `.env`: deployment settings, read by docker compose. Start from
  `.env.example`:
  - `POSTGRES_PASSWORD`: the database password. Postgres only applies it when
    it creates its volume, so changing it later needs `ALTER USER` as well.
  - `CONEX_HOST`: the hostname the UI is served at.
  - image settings and the optional LDAP service, see below.


### HTTPS
`conex-web` serves HTTPS on port 443 and redirects port 80 to it. The
certificate depends on `CONEX_HOST`:

- **Public domain** (e.g. `conex.example.com`): Let's Encrypt, renewed
  automatically. DNS must point at the host and ports 80 and 443 must be
  reachable from the internet.
- **`localhost`, an IP, or a `*.local`, `*.internal` or `*.home.arpa` name**:
  Caddy's own local CA. To get rid of the browser warning, export its root
  certificate and trust it on the client machines:

  ```sh
  docker compose cp conex-web:/data/caddy/pki/authorities/local/root.crt conex-root.crt
  ```

Certificates and the local CA live in the `conex-web-data` volume. Session
cookies are `Secure`, so logging in only works over HTTPS.

Behind another reverse proxy, forward to `conex-web` on port 443 and either
trust the local CA there or skip upstream certificate verification.

### AGFEO Dashboard (optional)
The `agfeo-ldap` service is in the `agfeo-ldap` compose profile, so it only
runs when that profile is enabled:

```sh
docker compose --profile agfeo-ldap up -d --build
```

To enable it permanently, set `COMPOSE_PROFILES=agfeo-ldap` in `.env`.

The service reaches conex at `http://conex:3000` and listens on port 1389 in
the container; `docker-compose.override.yml.example` publishes it as port 389.
Set the search base with `AGFEO_LDAP_BASE_DN` in `.env`. Without TLS, passwords cross the
network in plain text. For LDAPS, mount a certificate and key (see the
override example), set `AGFEO_LDAP_TLS_CERT` and `AGFEO_LDAP_TLS_KEY`, and
publish `636:1389`.

The conex user and the Dashboard account are set up as described in
`docs/integrations/agfeo.md` in conex.

## Building images

```sh
./build.sh                       # conex:main, conex-web:main from git
./build.sh v1.0.0 --push         # a tag, then push
./build.sh dev --src ../conex    # from a local checkout
./build.sh --agfeo-ldap          # also conex-agfeo-ldap:main
CONEX_IMAGE=ghcr.io/me/conex ./build.sh main
```

A local checkout also works with plain Docker:
`docker buildx build --build-context conex-src=../conex --target conex .`
(see `docker-compose.override.yml.example` for compose).

## Backup and restore
The database is in the `conex-postgres-data` volume, and the `conex-data`
volume holds the TANSS integration response dumps. Keep `config.toml` too:
losing its `appKey` logs out all sessions.

```sh
docker compose exec -T postgres pg_dump -U conex -Fc conex > conex-$(date +%F).dump
```

To restore into a fresh database:

```sh
docker compose stop conex
docker compose exec -T postgres pg_restore -U conex -d conex --clean --if-exists < conex-2026-10-01.dump
docker compose start conex
```

To back up `conex-data`:

```sh
docker run --rm -v conex-docker_conex-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/conex-data.tar.gz -C /data .
```

Database migrations run automatically on startup, so upgrading means
rebuilding with a newer `CONEX_VERSION` and running `docker compose up -d`.
