#!/bin/sh
# Builds the conex and conex-web images.
#
# Usage: ./build.sh [ref] [--src <path>] [--push]
#   ref           conex branch, tag or commit to build (default: dev-netbox)
#   --src <path>  build from a local conex checkout instead of git
#   --push        push the images after building
#
# Env: CONEX_IMAGE (default: conex), CONEX_TAG (default: ref with '/' -> '-')
set -eu

ref=dev-netbox
src=
push=

while [ $# -gt 0 ]; do
	case "$1" in
	--src)
		src="$2"
		shift 2
		;;
	--push)
		push=1
		shift
		;;
	-h | --help)
		sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		ref="$1"
		shift
		;;
	esac
done

image="${CONEX_IMAGE:-conex}"
tag="${CONEX_TAG:-$(printf '%s' "$ref" | tr '/' '-')}"

cd "$(dirname "$0")"

for target in conex conex-web; do
	name="$image"
	[ "$target" = conex-web ] && name="$image-web"

	set -- --target "$target" --build-arg "CONEX_VERSION=$ref" --tag "$name:$tag"
	[ -n "$src" ] && set -- "$@" --build-context "conex-src=$src"

	echo "==> Building $name:$tag"
	docker buildx build --load "$@" .

	if [ -n "$push" ]; then
		docker push "$name:$tag"
	fi
done
