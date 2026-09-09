#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=bootstrap/lib/core.sh
source "$ROOT/bootstrap/lib/core.sh"

TESTS=0
TMP=$(mktemp -d -t quickstart-tests.XXXXXXXXXX)
trap 'rm -rf "$TMP"' EXIT

pass() {
  TESTS=$((TESTS + 1))
}

expect_success() {
  local description=$1
  shift
  if ! "$@"; then
    printf 'FAIL: %s\n' "$description" >&2
    exit 1
  fi
  pass
}

expect_failure() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s (unexpected success)\n' "$description" >&2
    exit 1
  fi
  pass
}

expect_success "Debian 12 x86_64 is supported" qs_is_supported_platform debian 12 x86_64
expect_success "Debian 13 aarch64 is supported" qs_is_supported_platform debian 13 aarch64
expect_success "Ubuntu 26.04 is supported" qs_is_supported_platform ubuntu 26.04 x86_64
expect_failure "Fedora is rejected" qs_is_supported_platform fedora 43 x86_64
expect_failure "unsupported architecture is rejected" qs_is_supported_platform debian 13 riscv64

expect_success "main development ref is accepted" qs_validate_ref main
expect_failure "movable release tag is rejected" qs_validate_ref v1.2.3
expect_success "full commit ref is accepted" qs_validate_ref 0123456789abcdef0123456789abcdef01234567
expect_failure "short commit ref is rejected" qs_validate_ref deadbeef
expect_failure "moving feature branch is rejected" qs_validate_ref feature/bootstrap

[[ "$(qs_session_id_from_line $'   17 1000 aemon seat0 42 sshd remote')" == "17" ]] || {
  printf 'FAIL: padded loginctl session parsing\n' >&2
  exit 1
}
pass
expect_success "remote sshd session is accepted" qs_is_verified_ssh_session \
  aemon aemon yes active sshd 203.0.113.7
expect_failure "non-SSH remote session is rejected" qs_is_verified_ssh_session \
  aemon aemon yes active cron 203.0.113.7
expect_failure "session without remote host is rejected" qs_is_verified_ssh_session \
  aemon aemon yes active sshd ""

expect_success "canonical keys validate" qs_validate_authorized_keys "$ROOT/users/aemon/authorized_keys"
expect_success "fingerprint manifest matches" qs_verify_fingerprint_manifest \
  "$ROOT/users/aemon/authorized_keys" "$ROOT/users/aemon/authorized_keys.fingerprints"

head -n 5 "$ROOT/users/aemon/authorized_keys" >"$TMP/five-keys"
expect_failure "wrong key count is rejected" qs_validate_authorized_keys "$TMP/five-keys"

cat "$ROOT/users/aemon/authorized_keys" "$ROOT/users/aemon/authorized_keys" >"$TMP/duplicate-keys"
expect_failure "duplicate keys are rejected" qs_validate_authorized_keys "$TMP/duplicate-keys"

printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' >"$TMP/private-key"
expect_failure "private key material is rejected" qs_validate_authorized_keys "$TMP/private-key"

cp "$ROOT/users/aemon/authorized_keys.fingerprints" "$TMP/wrong-fingerprints"
printf '%s\n' 'SHA256:not-a-real-key' >>"$TMP/wrong-fingerprints"
expect_failure "fingerprint drift is rejected" qs_verify_fingerprint_manifest \
  "$ROOT/users/aemon/authorized_keys" "$TMP/wrong-fingerprints"

cat >"$TMP/good-policy" <<'POLICY'
pubkeyauthentication yes
authenticationmethods publickey
gssapiauthentication no
hostbasedauthentication no
authorizedkeysfile .ssh/authorized_keys
authorizedkeyscommand none
trustedusercakeys none
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin no
POLICY
expect_success "intended effective SSH policy is accepted" qs_assert_effective_policy "$TMP/good-policy"

sed 's/passwordauthentication no/passwordauthentication yes/' "$TMP/good-policy" >"$TMP/bad-policy"
expect_failure "password authentication is rejected" qs_assert_effective_policy "$TMP/bad-policy"

printf '%s\n' 1 2 >"$TMP/before"
printf '%s\n' 1 2 7 >"$TMP/after"
[[ "$(qs_new_items "$TMP/before" "$TMP/after")" == "7" ]] || {
  printf 'FAIL: new session detection\n' >&2
  exit 1
}
pass

printf 'PASS: %d core tests\n' "$TESTS"
