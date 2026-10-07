# conex-docker
Docker deployment for [conex](https://github.com/serkonda7/conex).

It builds the `main` branch by default. Two images come from one
`Dockerfile`, and compose adds a stock Postgres:

| Service     | Contents                                              | Port |
| ----------- | ----------------------------------------------------- | ---- |
| `conex`     | bun API server, state in the `/opt/conex/data` volume | 3000 |
| `conex-web` | Caddy serving the UI over HTTPS, proxying `/api/*`    | 443  |
| `postgres`  | `postgres:17-alpine`, the conex database              | 5432 |

Optional: `agfeo-ldap`, see [AGFEO Dashboard](#agfeo-dashboard-optional).


## Quickstart
```sh
git clone <this repo> conex-docker
cd conex-docker
cp docker-compose.override.yml.example docker-compose.override.yml
sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env.example > .env
sed "s/^appKey = .*/appKey = \"$(openssl rand -hex 48)\"/" config.toml.example > config.toml
docker compose up -d --build
```

Open <https://localhost> and create the admin account. For the certificate
warning, see [HTTPS](#https).


## Configuration
- `.env`: compose settings, from `.env.example`.
  - `POSTGRES_PASSWORD` only takes effect when the database volume is created.
- `config.toml`: server config, from `config.toml.example`. Needs an `appKey`
  of 32+ characters.


### HTTPS
Caddy redirects port 80 to 443 and picks the certificate by `CONEX_HOST`:

- public domain: Let's Encrypt (DNS and ports 80/443 must reach the host)
- `localhost`, IP, `*.local`, `*.internal`, `*.home.arpa`: Caddy's local CA

```sh
sed -i 's/^CONEX_HOST=.*/CONEX_HOST=conex.example.com/' .env
echo 'CONEX_TLS=internal' >> .env   # optional: local CA for a public domain too
docker compose up -d
```

Export the local CA's root certificate and trust it on the clients:

```sh
docker compose cp conex-web:/data/caddy/pki/authorities/local/root.crt conex-root.crt
```

Login needs HTTPS (`Secure` cookies). Behind another reverse proxy, forward
to `conex-web:443`.


### AGFEO Dashboard (optional)
LDAP contact directory for the AGFEO Dashboard, on host port 389:

```sh
echo 'COMPOSE_PROFILES=agfeo-ldap' >> .env
docker compose up -d --build
```

LDAPS (plain LDAP sends passwords unencrypted): put `cert.pem` and `key.pem`
into `certs/` (readable by uid 1000), uncomment the `volumes` of `agfeo-ldap` in
`docker-compose.override.yml` and change its port to `636:1389`, then:

```sh
printf '%s\n' AGFEO_LDAP_TLS_CERT=/etc/agfeo-ldap/cert.pem AGFEO_LDAP_TLS_KEY=/etc/agfeo-ldap/key.pem >> .env
docker compose up -d
```

conex user and Dashboard setup, see [conex docs](https://github.com/serkonda7/conex/blob/main/docs/integrations/agfeo.md).


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
