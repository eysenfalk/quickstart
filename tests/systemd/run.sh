#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
IMAGE=${SYSTEMD_TEST_IMAGE:-quickstart-systemd-test}
RUN_NIX=${RUN_NIX:-0}
TMP=$(mktemp -d -t quickstart-systemd.XXXXXXXXXX)
CONTAINER="quickstart-systemd-$$"
BOOTSTRAP_PID=""
LOGIN_PID=""
RERUN_COMMAND="sudo -n env SSH_CONNECTION=\"\$SSH_CONNECTION\" bash /repo/bootstrap/install.sh --source-dir /repo --ref main --skip-nix --login-timeout 60"

cleanup() {
  local status=$?
  if [[ -n "$LOGIN_PID" ]]; then
    kill "$LOGIN_PID" 2>/dev/null || true
  fi
  if [[ -n "$BOOTSTRAP_PID" ]]; then
    kill "$BOOTSTRAP_PID" 2>/dev/null || true
  fi
  docker rm --force "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP"
  exit "$status"
}
trap cleanup EXIT

cp -a "$ROOT/." "$TMP/repo"
: >"$TMP/repo/users/aemon/authorized_keys"
for number in 1 2 3 4 5 6; do
  ssh-keygen -q -t ed25519 -N '' -C "systemd-test-$number" -f "$TMP/aemon-key-$number"
  cat "$TMP/aemon-key-$number.pub" >>"$TMP/repo/users/aemon/authorized_keys"
done
ssh-keygen -lf "$TMP/repo/users/aemon/authorized_keys" -E sha256 |
  awk '{print $2}' >"$TMP/repo/users/aemon/authorized_keys.fingerprints"
git -C "$TMP/repo" add --all
git -C "$TMP/repo" -c user.name=Quickstart-Test -c user.email=test.invalid \
  commit --quiet --message 'systemd test fixture'
ssh-keygen -q -t ed25519 -N '' -C systemd-root -f "$TMP/root-key"
chmod -R a+rX "$TMP/repo"

docker build --quiet --tag "$IMAGE" --file "$ROOT/tests/systemd/Dockerfile" "$ROOT/tests/systemd" >/dev/null
docker run --privileged --detach --rm \
  --name "$CONTAINER" \
  --tmpfs /run --tmpfs /run/lock \
  --publish 127.0.0.1::22 \
  --volume "$TMP/repo:/repo:ro" \
  "$IMAGE" >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" systemctl is-active --quiet ssh.service 2>/dev/null; then
    break
  fi
  sleep 0.5
done
docker exec "$CONTAINER" systemctl is-active --quiet ssh.service

docker exec --interactive "$CONTAINER" bash -c '
  passwd -d root >/dev/null
  install -d -o root -g root -m 0700 /root/.ssh
  cat >/root/.ssh/authorized_keys
  chmod 0600 /root/.ssh/authorized_keys
' <"$TMP/root-key.pub"

PORT=$(docker port "$CONTAINER" 22/tcp)
PORT=${PORT##*:}
SSH_COMMON=(
  -o BatchMode=yes
  -o ConnectTimeout=3
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -p "$PORT"
)

start_aemon_session() {
  (
    for _ in $(seq 1 40); do
      if ssh "${SSH_COMMON[@]}" -i "$TMP/aemon-key-1" aemon@127.0.0.1 sleep 30; then
        exit 0
      fi
      sleep 0.5
    done
    exit 1
  ) &
  LOGIN_PID=$!
}

for _ in $(seq 1 30); do
  if ssh "${SSH_COMMON[@]}" -i "$TMP/root-key" root@127.0.0.1 true 2>/dev/null; then
    break
  fi
  sleep 0.5
done
if ! ssh "${SSH_COMMON[@]}" -i "$TMP/root-key" root@127.0.0.1 true; then
  docker logs "$CONTAINER" >&2
  docker exec "$CONTAINER" /usr/sbin/sshd -T -C user=root,host=localhost,addr=127.0.0.1 >&2
  exit 1
fi

# Interrupt exactly after final-drop-in replacement. The EXIT transaction must
# restore the previous keys and SSH policy, leaving the initial root path usable.
ssh "${SSH_COMMON[@]}" -i "$TMP/root-key" root@127.0.0.1 \
  'QUICKSTART_TEST_INTERRUPT_AFTER_FINAL=1 bash /repo/bootstrap/install.sh --source-dir /repo --ref main --skip-nix --login-timeout 60' \
  >"$TMP/bootstrap-interrupt.log" 2>&1 &
BOOTSTRAP_PID=$!
for _ in $(seq 1 120); do
  if docker exec "$CONTAINER" test -f /etc/ssh/sshd_config.d/00-quickstart-stage.conf 2>/dev/null; then
    break
  fi
  sleep 0.5
done
start_aemon_session
if wait "$BOOTSTRAP_PID"; then
  printf 'interruption failpoint unexpectedly succeeded\n' >&2
  exit 1
fi
BOOTSTRAP_PID=""
wait "$LOGIN_PID" || true
LOGIN_PID=""
docker exec "$CONTAINER" test ! -e /etc/ssh/sshd_config.d/00-quickstart.conf
docker exec "$CONTAINER" test ! -e /etc/ssh/sshd_config.d/00-quickstart-stage.conf
ssh "${SSH_COMMON[@]}" -i "$TMP/root-key" root@127.0.0.1 true
if ssh "${SSH_COMMON[@]}" -i "$TMP/aemon-key-1" aemon@127.0.0.1 true >/dev/null 2>&1; then
  printf 'aemon key unexpectedly remained after interrupted fresh handoff\n' >&2
  exit 1
fi

bootstrap_args=(--source-dir /repo --ref main --login-timeout 60)
[[ "$RUN_NIX" -eq 1 ]] || bootstrap_args+=(--skip-nix)
ssh "${SSH_COMMON[@]}" -i "$TMP/root-key" root@127.0.0.1 \
  bash /repo/bootstrap/install.sh "${bootstrap_args[@]}" >"$TMP/bootstrap-first.log" 2>&1 &
BOOTSTRAP_PID=$!

for _ in $(seq 1 120); do
  if docker exec "$CONTAINER" test -f /etc/ssh/sshd_config.d/00-quickstart-stage.conf 2>/dev/null; then
    break
  fi
  kill -0 "$BOOTSTRAP_PID" 2>/dev/null || {
    cat "$TMP/bootstrap-first.log" >&2
    docker exec "$CONTAINER" bash -c 'tail -n 200 /var/log/quickstart/bootstrap-*.log' >&2 || true
    exit 1
  }
  sleep 0.5
done

start_aemon_session
wait "$BOOTSTRAP_PID" || {
  cat "$TMP/bootstrap-first.log" >&2
  docker exec "$CONTAINER" bash -c 'tail -n 200 /var/log/quickstart/bootstrap-*.log' >&2 || true
  exit 1
}
BOOTSTRAP_PID=""
wait "$LOGIN_PID" || true
LOGIN_PID=""

if ssh "${SSH_COMMON[@]}" -i "$TMP/root-key" root@127.0.0.1 true >/dev/null 2>&1; then
  printf 'root SSH login unexpectedly succeeded after hardening\n' >&2
  exit 1
fi
ssh "${SSH_COMMON[@]}" -i "$TMP/aemon-key-1" aemon@127.0.0.1 sudo -n true
docker exec "$CONTAINER" test -f /var/lib/quickstart/last-bootstrap

effective=$(docker exec "$CONTAINER" /usr/sbin/sshd -T \
  -C user=aemon,host=localhost,addr=127.0.0.1)
printf '%s\n' "$effective" >"$TMP/effective-sshd"
qs_effective="$TMP/effective-sshd"
# shellcheck source=bootstrap/lib/core.sh
source "$ROOT/bootstrap/lib/core.sh"
qs_assert_effective_policy "$qs_effective"
rm -f "$qs_effective"

# Re-run from the managed account. A second aemon login is still required and
# both staged and final drop-ins coexist during this handoff.
if [[ "$RUN_NIX" -eq 1 ]]; then
  RERUN_COMMAND="sudo -n env SSH_CONNECTION=\"\$SSH_CONNECTION\" bash /repo/bootstrap/install.sh --source-dir /repo --ref main --login-timeout 60"
fi
ssh "${SSH_COMMON[@]}" -i "$TMP/aemon-key-1" aemon@127.0.0.1 \
  "$RERUN_COMMAND" >"$TMP/bootstrap-rerun.log" 2>&1 &
BOOTSTRAP_PID=$!
for _ in $(seq 1 120); do
  if docker exec "$CONTAINER" test -f /etc/ssh/sshd_config.d/00-quickstart-stage.conf 2>/dev/null; then
    break
  fi
  kill -0 "$BOOTSTRAP_PID" 2>/dev/null || {
    cat "$TMP/bootstrap-rerun.log" >&2
    docker exec "$CONTAINER" bash -c 'tail -n 200 /var/log/quickstart/bootstrap-*.log' >&2 || true
    exit 1
  }
  sleep 0.5
done
start_aemon_session
wait "$BOOTSTRAP_PID" || {
  cat "$TMP/bootstrap-rerun.log" >&2
  docker exec "$CONTAINER" bash -c 'tail -n 200 /var/log/quickstart/bootstrap-*.log' >&2 || true
  exit 1
}
BOOTSTRAP_PID=""
wait "$LOGIN_PID" || true
LOGIN_PID=""

printf 'PASS: full systemd SSH handoff, hardening, and idempotent rerun'
[[ "$RUN_NIX" -eq 1 ]] && printf ' with fresh Nix installation'
printf '\n'
