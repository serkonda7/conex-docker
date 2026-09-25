# conex-docker

Docker deployment for [conex](https://github.com/serkonda7/conex), laid out
like [netbox-docker](https://github.com/netbox-community/netbox-docker).

Two images come from one `Dockerfile`:

| Image       | Contents                                                  | Port |
| ----------- | --------------------------------------------------------- | ---- |
| `conex`     | bun API server, SQLite DB in the `/opt/conex/data` volume | 3000 |
| `conex-web` | Caddy serving the UI and proxying `/api/*` to `conex`     | 8080 |

## Quickstart

```sh
git clone <this repo> conex-docker
cd conex-docker
cp docker-compose.override.yml.example docker-compose.override.yml
docker compose up -d --build
```

Open <http://localhost:8000> and create the admin account in the first-run
dialog.

To build a different conex branch, tag or commit:

```sh
CONEX_VERSION=dev-netbox docker compose up -d --build
```

## Configuration

The settings live in `env/conex.env`. On every start the entrypoint turns
them into the server's `config.toml`:

| Variable                     | Default     | Meaning                                              |
| ---------------------------- | ----------- | ---------------------------------------------------- |
| `CONEX_APP_KEY`              | generated   | JWT signing secret, min. 32 chars                    |
| `CONEX_APP_KEY_FILE`         |             | Read the key from a file (Docker secret)             |
| `CONEX_SECURE_COOKIES`       | `false`\*   | Set to `true` when serving over HTTPS                |
| `CONEX_FRONTEND_URL`         |             | Public URL of the UI                                 |
| `CONEX_LOGIN_MAX_ATTEMPTS`   | `10`        | Login rate limit: attempts per window                |
| `CONEX_LOGIN_WINDOW_SECONDS` | `300`       | Login rate limit: window length                      |
| `CONEX_JWT_KEY_VERSION`      | `1`         | Increase it to invalidate all sessions               |
| `CONEX_CONFIG_PATH`          |             | Use a mounted `config.toml` instead of the variables |

\* The server defaults to `true`, but `env/conex.env` sets it to `false`
because the default setup serves plain HTTP.

If no app key is set, one is generated on first start and saved in
`data/.app_key` in the volume, so sessions survive restarts.

### HTTPS

Put a TLS-terminating reverse proxy in front of `conex-web`, then set
`CONEX_SECURE_COOKIES=true` and `CONEX_FRONTEND_URL=https://...`.

## Building images

```sh
./build.sh                       # conex:main, conex-web:main from git
./build.sh v1.0.0 --push         # a tag, then push
./build.sh dev --src ../conex    # from a local checkout
CONEX_IMAGE=ghcr.io/me/conex ./build.sh main
```

A local checkout also works with plain Docker:
`docker buildx build --build-context conex-src=../conex --target conex .`
(see `docker-compose.override.yml.example` for compose).

## Backup and restore

All state is in the `conex-data` volume: `conex.db` and `.app_key`.

```sh
docker compose stop conex
docker run --rm -v conex-docker_conex-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/conex-data.tar.gz -C /data .
docker compose start conex
```

To restore, extract the archive into the volume the same way while `conex`
is stopped. Database migrations run automatically on startup, so upgrading
means rebuilding with a newer `CONEX_VERSION` and running
`docker compose up -d`.
