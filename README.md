# conex-docker
Docker deployment for [conex](https://github.com/serkonda7/conex).

Two images built by the `Dockerfile`, and a stock Postgres.
Defaults to the conex `main` branch, see [Version](#version).

| Service     | Contents                                              | Port |
| ----------- | ----------------------------------------------------- | ---- |
| `conex`     | bun API server, state in the `/opt/conex/data` volume | 3000 |
| `conex-web` | Caddy serving the UI over HTTPS, proxying `/api/*`    | 443  |
| `postgres`  | `postgres:17-alpine`, the conex database              | 5432 |

Optional: `agfeo-ldap`, see [AGFEO Dashboard](#agfeo-dashboard-optional).


## Quickstart
```sh
git clone https://github.com/serkonda7/conex-docker conex-docker
cd conex-docker
cp docker-compose.override.yml.example docker-compose.override.yml
sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env.example > .env
sed "s/^appKey = .*/appKey = \"$(openssl rand -hex 48)\"/" config.toml.example > config.toml
docker compose up -d --build
```

Open <https://localhost> and create the admin account. For the certificate
warning, see [HTTPS](#https).


## Updating
```sh
# Backup data
docker compose exec -T postgres pg_dump -U conex -Fc conex > backups/conex-$(date +%F).dump
docker compose exec -T conex tar czf - -C /opt/conex/data . > backups/conex-data-$(date +%F).tar.gz

# Optional: pin a release, see Version
CONEX_VERSION=stable
sed -i "s/^#\?CONEX_VERSION=.*/CONEX_VERSION=$CONEX_VERSION/" .env

# Rebuild and restart
git pull
docker compose up -d --build

# Optional: drop old images
docker image prune -f
```


### Rollback
```sh
# Set previous release
CONEX_VERSION=1.1.0
BACKUP_DATE=2026-10-01

# Rebuild
docker compose stop conex
sed -i "s/^#\?CONEX_VERSION=.*/CONEX_VERSION=$CONEX_VERSION/" .env
docker compose build

# Restore
docker compose exec -T postgres pg_restore -U conex -d conex --clean --if-exists < backups/conex-$BACKUP_DATE.dump
docker compose run --rm --no-deps -v "$PWD/backups:/backup:ro" --entrypoint sh conex \
  -c "find /opt/conex/data -mindepth 1 -delete && tar xzf /backup/conex-data-$BACKUP_DATE.tar.gz -C /opt/conex/data"

# Restart
docker compose up -d
```


## Configuration
- `.env`: compose settings, from `.env.example`.
  - `POSTGRES_PASSWORD` only takes effect when the database volume is created.
- `config.toml`: server config, from `config.toml.example`. Needs an `appKey`
  of 32+ characters.


### Version
`CONEX_VERSION` in `.env` selects the conex source and is also the image tag:

- `main` (default): the `main` branch
- `stable`: the latest release tag
- a release tag, e.g. `1.1.0`

`docker compose up -d --build` fetches the latest commit or release.


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
