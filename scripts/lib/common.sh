#!/bin/sh

set -eu

KINETIC_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

kinetic_die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

kinetic_require() {
    command -v "$1" >/dev/null 2>&1 || kinetic_die "required command not found: $1"
}

kinetic_profile() {
    case "${1:-debug}" in
        debug | release) printf '%s\n' "${1:-debug}" ;;
        *) kinetic_die "expected profile 'debug' or 'release', got: $1" ;;
    esac
}

kinetic_build_dir() {
    printf '%s/build/%s\n' "$KINETIC_ROOT" "$1"
}

