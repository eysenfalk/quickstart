#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
IMAGE=${NIX_TEST_IMAGE:-nixos/nix:2.34.8}

docker run --rm --volume "$ROOT:/work:ro" --workdir /tmp "$IMAGE" sh -euc '
  nix_exp() {
    nix --extra-experimental-features "nix-command flakes" "$@"
  }

  nix_exp flake check path:/work
  nix_exp eval path:/work#homeConfigurations.\"aemon@aarch64-linux\".activationPackage.drvPath --raw >/dev/null

  cp -a /work /tmp/formatted
  chmod -R u+w /tmp/formatted
  nix_exp run path:/work#formatter.x86_64-linux -- \
    --ci --walk filesystem --tree-root /tmp/formatted /tmp/formatted
'

printf 'PASS: Nix evaluation, build, ARM64 evaluation, and formatting\n'
