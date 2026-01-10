#!/usr/bin/env bash
set -euo pipefail
TAG="v6.0.0"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 --branch "$TAG" https://github.com/knadh/listmonk.git "$TMP/listmonk"
pushd "$TMP/listmonk" >/dev/null
go test ./...
popd >/dev/null
echo "OK: go test ./... for listmonk $TAG"
