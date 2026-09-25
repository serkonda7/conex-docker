#!/bin/sh
# Renders the conex config.toml from environment variables, then runs CMD.
#
# - CONEX_CONFIG_PATH set: that file is used as-is, nothing is rendered.
# - Otherwise the config is rendered to /tmp/conex/config.toml on every start,
#   so the env files stay the single source of truth.
# - CONEX_APP_KEY (or CONEX_APP_KEY_FILE) missing: a random key is generated
#   once and persisted in the data volume (data/.app_key).
set -eu

DATA_DIR=/opt/conex/data

toml_bool() {
	case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
	true | 1 | yes | on) echo true ;;
	false | 0 | no | off) echo false ;;
	*)
		echo "conex-entrypoint: invalid boolean '$1'" >&2
		exit 1
		;;
	esac
}

toml_string() {
	printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

resolve_app_key() {
	if [ -n "${CONEX_APP_KEY_FILE:-}" ]; then
		tr -d '\r\n' <"$CONEX_APP_KEY_FILE"
	elif [ -n "${CONEX_APP_KEY:-}" ]; then
		printf '%s' "$CONEX_APP_KEY"
	else
		key_file="$DATA_DIR/.app_key"
		if [ ! -s "$key_file" ]; then
			echo "conex-entrypoint: no CONEX_APP_KEY set, generating one in $key_file" >&2
			(umask 077 && head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$key_file")
		fi
		cat "$key_file"
	fi
}

if [ -z "${CONEX_CONFIG_PATH:-}" ]; then
	app_key="$(resolve_app_key)"
	if [ "${#app_key}" -lt 32 ]; then
		echo "conex-entrypoint: app key must be at least 32 characters" >&2
		exit 1
	fi

	mkdir -p /tmp/conex
	config=/tmp/conex/config.toml
	(
		umask 077
		{
			if [ -n "${CONEX_FRONTEND_URL:-}" ]; then
				echo "frontendUrl = $(toml_string "$CONEX_FRONTEND_URL")"
				echo
			fi
			echo "[auth]"
			echo "appKey = $(toml_string "$app_key")"
			echo "jwtKeyVersion = ${CONEX_JWT_KEY_VERSION:-1}"
			echo "secureCookies = $(toml_bool "${CONEX_SECURE_COOKIES:-true}")"
			echo
			echo "[auth.loginRateLimit]"
			echo "maxAttempts = ${CONEX_LOGIN_MAX_ATTEMPTS:-10}"
			echo "windowSeconds = ${CONEX_LOGIN_WINDOW_SECONDS:-300}"
		} >"$config"
	)
	export CONEX_CONFIG_PATH="$config"
fi

exec "$@"
