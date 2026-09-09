#!/usr/bin/env bash

# Pure and reusable helpers for the Quickstart bootstrap.

qs_error() {
  printf 'quickstart: error: %s\n' "$*" >&2
}

qs_is_supported_platform() {
  local os_id=${1:-}
  local version=${2:-}
  local arch=${3:-}

  case "$arch" in
    x86_64 | aarch64) ;;
    *) return 1 ;;
  esac

  case "${os_id}:${version}" in
    debian:12 | debian:13 | ubuntu:22.04 | ubuntu:24.04 | ubuntu:26.04) return 0 ;;
    *) return 1 ;;
  esac
}

qs_validate_ref() {
  local ref=${1:-}
  [[ "$ref" == "main" || "$ref" =~ ^[0-9a-f]{40}$ ]]
}

qs_validate_authorized_keys() {
  local file=$1
  local line algorithm blob rest count=0
  local seen
  seen=$(mktemp)

  if [[ ! -s "$file" ]]; then
    qs_error "authorized_keys source is empty: $file"
    rm -f "$seen"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" || "$line" == *$'\r'* || "$line" == '-----BEGIN '* ]]; then
      qs_error "invalid public-key line in $file"
      rm -f "$seen"
      return 1
    fi

    algorithm=${line%% *}
    rest=${line#* }
    if [[ "$rest" == "$line" ]]; then
      qs_error "public-key line has no key body"
      rm -f "$seen"
      return 1
    fi
    blob=${rest%% *}

    if [[ "$algorithm" != "ssh-ed25519" || ! "$blob" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
      qs_error "only well-formed ssh-ed25519 keys are accepted"
      rm -f "$seen"
      return 1
    fi

    printf '%s %s\n' "$algorithm" "$blob" >>"$seen"
    count=$((count + 1))
  done <"$file"

  if [[ "$count" -ne 6 ]]; then
    qs_error "expected exactly 6 public keys, found $count"
    rm -f "$seen"
    return 1
  fi

  if [[ "$(sort "$seen" | uniq | wc -l)" -ne "$count" ]]; then
    qs_error "duplicate public keys are not allowed"
    rm -f "$seen"
    return 1
  fi

  rm -f "$seen"
  ssh-keygen -lf "$file" >/dev/null 2>&1 || {
    qs_error "ssh-keygen rejected the public-key file"
    return 1
  }
}

qs_verify_fingerprint_manifest() {
  local keys_file=$1
  local manifest_file=$2
  local actual expected
  actual=$(mktemp)
  expected=$(mktemp)

  ssh-keygen -lf "$keys_file" | awk '{print $2}' | LC_ALL=C sort >"$actual"
  LC_ALL=C sort "$manifest_file" >"$expected"

  if ! cmp -s "$actual" "$expected"; then
    qs_error "public-key fingerprints do not match the release manifest"
    rm -f "$actual" "$expected"
    return 1
  fi

  rm -f "$actual" "$expected"
}

qs_effective_value() {
  local file=$1
  local keyword=$2
  awk -v key="$keyword" '$1 == key { print $2; exit }' "$file"
}

qs_assert_key_source_policy() {
  local file=$1
  local key expected actual

  while IFS=' ' read -r key expected; do
    actual=$(qs_effective_value "$file" "$key")
    if [[ "$actual" != "$expected" ]]; then
      qs_error "effective sshd policy has ${key}=${actual:-missing}, expected $expected"
      return 1
    fi
  done <<'POLICY'
pubkeyauthentication yes
authenticationmethods publickey
gssapiauthentication no
hostbasedauthentication no
authorizedkeysfile .ssh/authorized_keys
authorizedkeyscommand none
trustedusercakeys none
POLICY
}

qs_assert_effective_policy() {
  local file=$1
  local key expected actual

  qs_assert_key_source_policy "$file" || return 1

  while IFS=' ' read -r key expected; do
    actual=$(qs_effective_value "$file" "$key")
    if [[ "$actual" != "$expected" ]]; then
      qs_error "effective sshd policy has ${key}=${actual:-missing}, expected $expected"
      return 1
    fi
  done <<'POLICY'
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin no
POLICY
}

qs_new_items() {
  local before=$1
  local after=$2
  comm -13 <(LC_ALL=C sort -u "$before") <(LC_ALL=C sort -u "$after")
}

qs_session_id_from_line() {
  local line=$1
  if [[ "$line" =~ ^[[:space:]]*([^[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

qs_is_verified_ssh_session() {
  local expected_user=$1
  local actual_user=$2
  local remote=$3
  local state=$4
  local service=$5
  local remote_host=$6

  [[ "$actual_user" == "$expected_user" && "$remote" == "yes" &&
    "$service" == "sshd" && -n "$remote_host" && "$state" != "closing" ]]
}
