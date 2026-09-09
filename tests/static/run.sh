#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

bash -n "$ROOT/bootstrap/install.sh" "$ROOT/bootstrap/lib/core.sh" \
  "$ROOT/tests/static/core_test.sh"
shellcheck -x "$ROOT/bootstrap/install.sh" "$ROOT/bootstrap/lib/core.sh" \
  "$ROOT/tests/static/core_test.sh" "$ROOT/tests/static/run.sh" \
  "$ROOT/tests/container/run.sh" "$ROOT/tests/container/ssh_smoke.sh" \
  "$ROOT/tests/nix/run.sh" "$ROOT/tests/systemd/run.sh"
"$ROOT/tests/static/core_test.sh"
"$ROOT/bootstrap/install.sh" --help >/dev/null

git -C "$ROOT" diff --check
printf 'PASS: static validation\n'
