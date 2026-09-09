#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if (($#)); then
  images=("$@")
else
  images=(debian:13-slim ubuntu:26.04)
fi

for image in "${images[@]}"; do
  printf '\n==> Testing %s\n' "$image"
  docker run --rm --volume "$ROOT:/repo:ro" "$image" bash /repo/tests/container/ssh_smoke.sh
done

printf '\nPASS: container SSH matrix\n'
