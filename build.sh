#!/bin/sh
# Builds the conex and conex-web images.
#
# Usage: ./build.sh [ref] [--src <path>] [--agfeo-ldap] [--push]
#   ref           conex branch, tag or commit to build (default: main)
#   --src <path>  build from a local conex checkout instead of git
#   --agfeo-ldap  also build the conex-agfeo-ldap image
#   --push        push the images after building
#
# Env: CONEX_IMAGE (default: conex), CONEX_TAG (default: ref with '/' -> '-')
set -eu

ref=main
src=
push=
targets='conex conex-web'

while [ $# -gt 0 ]; do
	case "$1" in
	--src)
		src="$2"
		shift 2
		;;
	--agfeo-ldap)
		targets="$targets agfeo-ldap"
		shift
		;;
	--push)
		push=1
		shift
		;;
	-h | --help)
		sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
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

for target in $targets; do
	case "$target" in
	conex) name="$image" ;;
	conex-web) name="$image-web" ;;
	*) name="$image-$target" ;;
	esac

	set -- --target "$target" --build-arg "CONEX_VERSION=$ref" --tag "$name:$tag"
	[ -n "$src" ] && set -- "$@" --build-context "conex-src=$src"

	echo "==> Building $name:$tag"
	docker buildx build --load "$@" .

	if [ -n "$push" ]; then
		docker push "$name:$tag"
	fi
done
