#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

readonly ADMIN_USER="aemon"
readonly REPOSITORY_URL="https://github.com/eysenfalk/quickstart.git"
readonly RAW_BASE_URL="https://raw.githubusercontent.com/eysenfalk/quickstart"
readonly NIX_VERSION="2.34.8"
readonly NIX_INSTALLER_SHA256="96c10e102c88809dd9ec0bee89200c4a51eae4c9f6d8698c26b16788d131e078"
readonly NIX_INSTALLER_URL="https://releases.nixos.org/nix/nix-${NIX_VERSION}/install"
readonly MANAGED_SSH_CONFIG="/etc/ssh/sshd_config.d/00-quickstart.conf"
readonly STAGED_SSH_CONFIG="/etc/ssh/sshd_config.d/00-quickstart-stage.conf"
readonly INSTALL_ROOT="/opt/quickstart"

QUICKSTART_REF=${QUICKSTART_REF:-main}
SOURCE_DIR=${QUICKSTART_SOURCE_DIR:-}
LOGIN_TIMEOUT=${QUICKSTART_LOGIN_TIMEOUT:-600}
DRY_RUN=0
SKIP_NIX=0
ALLOW_CONSOLE=0
TMP_DIR=""
LOCK_FILE="/run/lock/quickstart-bootstrap.lock"
LOG_FILE=""
ROLLBACK_DIR=""
SSH_SERVICE=""
CLIENT_ADDRESS="127.0.0.1"
HANDOFF_ARMED=0
VERIFIED_SESSION_ID=""

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Options:
  --ref REF             Full 40-character Git commit (main: development only)
  --source-dir DIR      Use a local checkout instead of downloading files
  --login-timeout SEC   Wait this long for a new aemon SSH session (default: 600)
  --dry-run             Run preflight checks without changing the host
  --skip-nix            Stop after account and SSH setup
  --console             Permit launch outside an existing SSH session
  -h, --help            Show this help

The normal flow must run as root in the provider-supplied SSH session. It pauses
until a real second SSH login as aemon is observed, then activates key-only SSH.
USAGE
}

while (($#)); do
  case "$1" in
    --ref)
      [[ $# -ge 2 ]] || { printf 'quickstart: --ref requires a value\n' >&2; exit 2; }
      QUICKSTART_REF=$2
      shift 2
      ;;
    --source-dir)
      [[ $# -ge 2 ]] || { printf 'quickstart: --source-dir requires a value\n' >&2; exit 2; }
      SOURCE_DIR=$2
      shift 2
      ;;
    --login-timeout)
      [[ $# -ge 2 ]] || { printf 'quickstart: --login-timeout requires a value\n' >&2; exit 2; }
      LOGIN_TIMEOUT=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-nix)
      SKIP_NIX=1
      shift
      ;;
    --console)
      ALLOW_CONSOLE=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'quickstart: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$LOGIN_TIMEOUT" =~ ^[0-9]+$ ]] || ((LOGIN_TIMEOUT < 30 || LOGIN_TIMEOUT > 3600)); then
  printf 'quickstart: login timeout must be between 30 and 3600 seconds\n' >&2
  exit 2
fi

fetch() {
  local url=$1
  local destination=$2

  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 --fail --show-error --location "$url" -o "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget --https-only --quiet "$url" -O "$destination"
  else
    printf 'quickstart: curl or wget is required\n' >&2
    return 1
  fi
}

cleanup() {
  local status=$?
  if [[ "$HANDOFF_ARMED" -eq 1 && -n "$ROLLBACK_DIR" && -d "$ROLLBACK_DIR" ]]; then
    qs_error "bootstrap interrupted during SSH handoff; restoring prior access state"
    restore_staged_access || true
  fi
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

TMP_DIR=$(mktemp -d -t quickstart.XXXXXXXXXX)

materialize() {
  local relative_path=$1
  local destination=$2

  if [[ -n "$SOURCE_DIR" ]]; then
    [[ -f "$SOURCE_DIR/$relative_path" ]] || {
      printf 'quickstart: missing local source file: %s\n' "$SOURCE_DIR/$relative_path" >&2
      return 1
    }
    cp "$SOURCE_DIR/$relative_path" "$destination"
  else
    fetch "$RAW_BASE_URL/$QUICKSTART_REF/$relative_path" "$destination"
  fi
}

materialize "bootstrap/lib/core.sh" "$TMP_DIR/core.sh"
# shellcheck source=bootstrap/lib/core.sh
source "$TMP_DIR/core.sh"

log() {
  local message
  message="$(date -u +'%Y-%m-%dT%H:%M:%SZ') $*"
  printf '%s\n' "$message"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$message" >&3
  fi
}

run_logged() {
  if [[ -n "$LOG_FILE" ]]; then
    "$@" >>"$LOG_FILE" 2>&1
  else
    "$@"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    qs_error "required command is unavailable: $1"
    return 1
  }
}

preflight() {
  local os_id version arch

  [[ "$EUID" -eq 0 ]] || {
    qs_error "the bootstrap must run as root"
    return 1
  }
  [[ -r /etc/os-release ]] || {
    qs_error "/etc/os-release is missing"
    return 1
  }

  # Distribution-owned and safe to source: simple KEY=VALUE assignments.
  # shellcheck disable=SC1091
  source /etc/os-release
  os_id=${ID:-}
  version=${VERSION_ID:-}
  arch=$(uname -m)

  qs_is_supported_platform "$os_id" "$version" "$arch" || {
    qs_error "unsupported platform: ${os_id:-unknown} ${version:-unknown} ${arch:-unknown}"
    return 1
  }
  qs_validate_ref "$QUICKSTART_REF" || {
    qs_error "ref must be main or a full 40-character Git commit"
    return 1
  }
  [[ -d /run/systemd/system ]] || {
    qs_error "systemd must be running"
    return 1
  }
  require_command apt-get
  require_command flock

  if [[ -z "${SSH_CONNECTION:-}" && "$ALLOW_CONSOLE" -ne 1 ]]; then
    qs_error "no SSH session detected; use --console only from a verified recovery console"
    return 1
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    CLIENT_ADDRESS=${SSH_CONNECTION%% *}
  fi

  log "preflight passed for $os_id $version $arch (ref=$QUICKSTART_REF)"
  if [[ "$QUICKSTART_REF" == "main" ]]; then
    log "WARNING: main is mutable; use a full commit for a real server"
  fi
}

setup_logging() {
  local timestamp
  timestamp=$(date -u +'%Y%m%dT%H%M%SZ')
  install -d -m 0700 /var/log/quickstart
  LOG_FILE="/var/log/quickstart/bootstrap-$timestamp.log"
  : >"$LOG_FILE"
  chmod 0600 "$LOG_FILE"
  exec 3>>"$LOG_FILE"

  ROLLBACK_DIR="/var/lib/quickstart/rollback-$timestamp"
  install -d -m 0700 "$ROLLBACK_DIR"
}

install_prerequisites() {
  log "installing minimum Debian/Ubuntu prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  run_logged apt-get update
  run_logged apt-get install -y --no-install-recommends \
    ca-certificates coreutils curl git libpam-systemd openssh-client openssh-server sudo util-linux xz-utils

  local command
  for command in adduser awk cmp flock install loginctl ssh-keygen sshd systemctl visudo; do
    require_command "$command"
  done

  if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
    SSH_SERVICE=ssh.service
  elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
    SSH_SERVICE=sshd.service
  else
    qs_error "could not identify the OpenSSH systemd service"
    return 1
  fi
  systemctl is-active --quiet "$SSH_SERVICE" || run_logged systemctl start "$SSH_SERVICE"
}

acquire_bootstrap_lock() {
  install -d -o root -g root -m 0755 "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  if ! flock --nonblock 9; then
    qs_error "another bootstrap process holds $LOCK_FILE"
    return 1
  fi
}

install_admin_account() {
  local sudoers_temp="$TMP_DIR/sudoers-aemon"

  if id "$ADMIN_USER" >/dev/null 2>&1; then
    [[ "$(getent passwd "$ADMIN_USER" | cut -d: -f6)" == "/home/$ADMIN_USER" ]] || {
      qs_error "existing $ADMIN_USER account has an unexpected home directory"
      return 1
    }
  else
    log "creating administrative user $ADMIN_USER"
    run_logged adduser --disabled-password --gecos "" --home "/home/$ADMIN_USER" --shell /bin/bash "$ADMIN_USER"
  fi

  run_logged usermod --shell /bin/bash --append --groups sudo "$ADMIN_USER"
  run_logged passwd --lock "$ADMIN_USER"

  printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$ADMIN_USER" >"$sudoers_temp"
  chmod 0440 "$sudoers_temp"
  visudo -cf "$sudoers_temp" >>"$LOG_FILE" 2>&1
  install -o root -g root -m 0440 "$sudoers_temp" "/etc/sudoers.d/90-quickstart-$ADMIN_USER"
  visudo -c >>"$LOG_FILE" 2>&1
}

prepare_access_rollback() {
  if [[ -f "$MANAGED_SSH_CONFIG" ]]; then
    cp -a "$MANAGED_SSH_CONFIG" "$ROLLBACK_DIR/00-quickstart.conf.before"
  else
    : >"$ROLLBACK_DIR/00-quickstart.conf.absent"
  fi
}

install_authorized_keys() {
  local keys_source="$TMP_DIR/authorized_keys"
  local fingerprints_source="$TMP_DIR/authorized_keys.fingerprints"
  local ssh_dir="/home/$ADMIN_USER/.ssh"
  local target="$ssh_dir/authorized_keys"
  local target_temp="$ssh_dir/.authorized_keys.quickstart.$$"

  materialize "users/$ADMIN_USER/authorized_keys" "$keys_source"
  materialize "users/$ADMIN_USER/authorized_keys.fingerprints" "$fingerprints_source"
  qs_validate_authorized_keys "$keys_source"
  qs_verify_fingerprint_manifest "$keys_source" "$fingerprints_source"

  install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0700 "$ssh_dir"
  if [[ -f "$target" ]]; then
    cp -a "$target" "$ROLLBACK_DIR/authorized_keys.before"
  else
    : >"$ROLLBACK_DIR/authorized_keys.absent"
  fi

  install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0600 "$keys_source" "$target_temp"
  mv -f "$target_temp" "$target"
  chown "$ADMIN_USER:$ADMIN_USER" "$target"
  chmod 0600 "$target"
  qs_verify_fingerprint_manifest "$target" "$fingerprints_source"
  log "installed 6 verified public keys for $ADMIN_USER"
}

restore_staged_access() {
  local target="/home/$ADMIN_USER/.ssh/authorized_keys"

  rm -f "$STAGED_SSH_CONFIG"
  if [[ -f "$ROLLBACK_DIR/authorized_keys.before" ]]; then
    install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0600 \
      "$ROLLBACK_DIR/authorized_keys.before" "$target"
  elif [[ -f "$ROLLBACK_DIR/authorized_keys.absent" ]]; then
    rm -f "$target"
  fi
  restore_managed_sshd_config
}

sshd_output() {
  local user=$1
  local destination=$2
  local host
  host=$(hostname -f 2>/dev/null || hostname)
  sshd -T -C "user=$user,host=$host,addr=$CLIENT_ADDRESS" >"$destination"
}

validate_sshd_syntax() {
  sshd -t >>"$LOG_FILE" 2>&1
}

reload_sshd() {
  run_logged systemctl reload "$SSH_SERVICE"
}

remote_sessions() {
  local wanted_user=$1
  local session_line session_id user remote state service remote_host

  while IFS= read -r session_line; do
    session_id=$(qs_session_id_from_line "$session_line" || true)
    [[ -n "$session_id" ]] || continue
    user=$(loginctl show-session "$session_id" --property=Name --value 2>/dev/null || true)
    remote=$(loginctl show-session "$session_id" --property=Remote --value 2>/dev/null || true)
    state=$(loginctl show-session "$session_id" --property=State --value 2>/dev/null || true)
    service=$(loginctl show-session "$session_id" --property=Service --value 2>/dev/null || true)
    remote_host=$(loginctl show-session "$session_id" --property=RemoteHost --value 2>/dev/null || true)
    if qs_is_verified_ssh_session "$wanted_user" "$user" "$remote" "$state" "$service" "$remote_host"; then
      printf '%s\n' "$session_id"
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
}

stage_public_key_access() {
  local staged="$TMP_DIR/sshd-staged-aemon"

  log "staging a key-only policy for $ADMIN_USER while preserving root access"
  install -d -o root -g root -m 0755 /etc/ssh/sshd_config.d
  materialize "ssh/sshd-stage.conf" "$TMP_DIR/sshd-stage.conf"
  install -o root -g root -m 0644 "$TMP_DIR/sshd-stage.conf" "$STAGED_SSH_CONFIG"
  if ! validate_sshd_syntax || ! sshd_output "$ADMIN_USER" "$staged" ||
    ! qs_assert_key_source_policy "$staged" ||
    [[ "$(qs_effective_value "$staged" passwordauthentication)" != "no" ]] ||
    [[ "$(qs_effective_value "$staged" kbdinteractiveauthentication)" != "no" ]]; then
    rm -f "$STAGED_SSH_CONFIG"
    qs_error "could not establish the staged aemon key policy"
    return 1
  fi
  reload_sshd
}

assert_verified_session() {
  local session_id=$1
  local user remote state service remote_host

  user=$(loginctl show-session "$session_id" --property=Name --value 2>/dev/null || true)
  remote=$(loginctl show-session "$session_id" --property=Remote --value 2>/dev/null || true)
  state=$(loginctl show-session "$session_id" --property=State --value 2>/dev/null || true)
  service=$(loginctl show-session "$session_id" --property=Service --value 2>/dev/null || true)
  remote_host=$(loginctl show-session "$session_id" --property=RemoteHost --value 2>/dev/null || true)

  if ! qs_is_verified_ssh_session \
    "$ADMIN_USER" "$user" "$remote" "$state" "$service" "$remote_host"; then
    qs_error "verified aemon SSH session $session_id is no longer safely active"
    return 1
  fi
  CLIENT_ADDRESS=$remote_host
}

wait_for_verified_login() {
  local before="$TMP_DIR/sessions-before"
  local after="$TMP_DIR/sessions-after"
  local started now elapsed new_session

  remote_sessions "$ADMIN_USER" >"$before"
  started=$(date +%s)

  printf '\nOpen a SECOND terminal now and log in with a configured key:\n\n'
  printf '    ssh %s@<server-address>\n\n' "$ADMIN_USER"
  printf 'Quickstart will continue automatically after observing that SSH session.\n'
  printf 'Timeout: %s seconds. Keep both SSH sessions open.\n\n' "$LOGIN_TIMEOUT"

  while true; do
    remote_sessions "$ADMIN_USER" >"$after"
    new_session=$(qs_new_items "$before" "$after" | head -n 1 || true)
    if [[ -n "$new_session" ]] && assert_verified_session "$new_session"; then
      VERIFIED_SESSION_ID=$new_session
      log "verified new remote $ADMIN_USER SSH login (systemd session $new_session from $CLIENT_ADDRESS)"
      return 0
    fi

    now=$(date +%s)
    elapsed=$((now - started))
    if ((elapsed >= LOGIN_TIMEOUT)); then
      qs_error "no new remote $ADMIN_USER SSH login observed; SSH hardening was not activated"
      return 1
    fi
    sleep 2
  done
}

restore_managed_sshd_config() {
  rm -f "$STAGED_SSH_CONFIG"
  if [[ -f "$ROLLBACK_DIR/00-quickstart.conf.before" ]]; then
    install -o root -g root -m 0644 \
      "$ROLLBACK_DIR/00-quickstart.conf.before" "$MANAGED_SSH_CONFIG"
  elif [[ -f "$ROLLBACK_DIR/00-quickstart.conf.absent" ]]; then
    rm -f "$MANAGED_SSH_CONFIG"
  else
    qs_error "managed sshd rollback metadata is missing"
    return 1
  fi
  if ! validate_sshd_syntax; then
    qs_error "restored sshd configuration is invalid"
    return 1
  fi
  reload_sshd || true
}

activate_sshd_hardening() {
  local hardening_source="$TMP_DIR/sshd-hardening.conf"
  local effective_aemon="$TMP_DIR/sshd-final-aemon"
  local effective_root="$TMP_DIR/sshd-final-root"

  assert_verified_session "$VERIFIED_SESSION_ID" || return 1
  materialize "ssh/sshd-hardening.conf" "$hardening_source"

  install -d -o root -g root -m 0755 /etc/ssh/sshd_config.d
  install -o root -g root -m 0644 "$hardening_source" "$MANAGED_SSH_CONFIG"
  rm -f "$STAGED_SSH_CONFIG"
  if [[ "${QUICKSTART_TEST_INTERRUPT_AFTER_FINAL:-0}" == "1" ]]; then
    [[ -n "$SOURCE_DIR" ]] || {
      qs_error "the interruption test hook requires --source-dir"
      return 1
    }
    kill -TERM "$$"
  fi

  if ! validate_sshd_syntax || ! sshd_output "$ADMIN_USER" "$effective_aemon" ||
    ! sshd_output root "$effective_root" ||
    ! qs_assert_effective_policy "$effective_aemon" ||
    ! qs_assert_effective_policy "$effective_root"; then
    qs_error "final sshd policy validation failed; restoring previous configuration"
    restore_managed_sshd_config
    return 1
  fi

  assert_verified_session "$VERIFIED_SESSION_ID" || {
    restore_managed_sshd_config
    return 1
  }

  if ! reload_sshd; then
    qs_error "sshd reload failed; restoring previous configuration"
    restore_managed_sshd_config
    return 1
  fi

  sshd_output "$ADMIN_USER" "$effective_aemon"
  sshd_output root "$effective_root"
  if ! qs_assert_effective_policy "$effective_aemon" ||
    ! qs_assert_effective_policy "$effective_root" ||
    ! assert_verified_session "$VERIFIED_SESSION_ID"; then
    qs_error "post-reload SSH validation failed; restoring previous configuration"
    restore_managed_sshd_config
    return 1
  fi

  HANDOFF_ARMED=0
  log "activated key-only SSH; direct root SSH login is disabled"
}

checkout_source() {
  local origin resolved

  if [[ -n "$SOURCE_DIR" ]]; then
    printf '%s\n' "$SOURCE_DIR"
    return 0
  fi

  if [[ -e "$INSTALL_ROOT" && ! -d "$INSTALL_ROOT/.git" ]]; then
    qs_error "$INSTALL_ROOT exists but is not a Quickstart Git checkout"
    return 1
  fi

  if [[ ! -d "$INSTALL_ROOT/.git" ]]; then
    install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0755 "$INSTALL_ROOT"
    run_logged sudo -u "$ADMIN_USER" -H git clone --filter=blob:none "$REPOSITORY_URL" "$INSTALL_ROOT"
  else
    chown -R -h "$ADMIN_USER:$ADMIN_USER" "$INSTALL_ROOT"
  fi

  origin=$(sudo -u "$ADMIN_USER" -H git -C "$INSTALL_ROOT" remote get-url origin)
  [[ "$origin" == "$REPOSITORY_URL" ]] || {
    qs_error "$INSTALL_ROOT has an unexpected Git origin"
    return 1
  }

  run_logged sudo -u "$ADMIN_USER" -H git -C "$INSTALL_ROOT" fetch --force origin "$QUICKSTART_REF"
  resolved=$(sudo -u "$ADMIN_USER" -H git -C "$INSTALL_ROOT" rev-parse --verify FETCH_HEAD)
  if [[ "$QUICKSTART_REF" != "main" && "$resolved" != "$QUICKSTART_REF" ]]; then
    qs_error "fetched revision $resolved does not match requested commit $QUICKSTART_REF"
    return 1
  fi
  run_logged sudo -u "$ADMIN_USER" -H git -C "$INSTALL_ROOT" checkout --detach --force "$resolved"
  run_logged sudo -u "$ADMIN_USER" -H git -C "$INSTALL_ROOT" clean -dffx
  printf '%s\n' "$INSTALL_ROOT"
}

nix_binary() {
  [[ -x /nix/var/nix/profiles/default/bin/nix ]] || return 1
  printf '%s\n' /nix/var/nix/profiles/default/bin/nix
}

validate_nix_installation() {
  local nix version store_owner store_group

  nix=$(nix_binary) || {
    qs_error "the expected multi-user Nix binary is missing"
    return 1
  }
  version=$("$nix" --version)
  [[ "${version##* }" == "$NIX_VERSION" ]] || {
    qs_error "installed Nix version is ${version##* }, expected $NIX_VERSION"
    return 1
  }
  getent group nixbld >/dev/null || {
    qs_error "Nix build group nixbld is missing"
    return 1
  }
  store_owner=$(stat -c '%U' /nix/store 2>/dev/null || true)
  store_group=$(stat -c '%G' /nix/store 2>/dev/null || true)
  [[ "$store_owner" == "root" && "$store_group" == "nixbld" ]] || {
    qs_error "Nix store ownership is $store_owner:$store_group, expected root:nixbld"
    return 1
  }
  systemctl is-active --quiet nix-daemon.service || {
    qs_error "Nix daemon is not active"
    return 1
  }
  sudo -u "$ADMIN_USER" -H "$nix" --extra-experimental-features nix-command \
    store ping --store daemon >/dev/null || {
    qs_error "$ADMIN_USER cannot reach the Nix daemon"
    return 1
  }
}

install_nix() {
  local installer="$TMP_DIR/nix-install-${NIX_VERSION}.sh"

  if nix_binary >/dev/null 2>&1; then
    log "validating existing pinned Nix installation"
    validate_nix_installation
    return 0
  fi
  if [[ -e /nix ]] || command -v nix >/dev/null 2>&1; then
    qs_error "an incompatible or incomplete Nix installation already exists; recover it before rerunning"
    return 1
  fi

  log "installing pinned official Nix $NIX_VERSION in multi-user mode"
  fetch "$NIX_INSTALLER_URL" "$installer"
  printf '%s  %s\n' "$NIX_INSTALLER_SHA256" "$installer" | sha256sum --check --status - || {
    qs_error "Nix installer checksum verification failed"
    return 1
  }
  chmod 0755 "$installer"
  run_logged sh "$installer" --daemon --yes
  validate_nix_installation
}

activate_home_manager() {
  local source nix activation nix_system configuration backup_extension
  source=$(checkout_source)
  nix=$(nix_binary)

  case "$(uname -m)" in
    x86_64) nix_system="x86_64-linux" ;;
    aarch64) nix_system="aarch64-linux" ;;
    *)
      qs_error "Home Manager has no configuration for $(uname -m)"
      return 1
      ;;
  esac
  configuration="homeConfigurations.\"$ADMIN_USER@$nix_system\".activationPackage"

  log "checking and building Home Manager configuration for $nix_system"
  run_logged sudo -u "$ADMIN_USER" -H "$nix" --extra-experimental-features "nix-command flakes" \
    flake check "$source"
  activation=$(sudo -u "$ADMIN_USER" -H "$nix" --extra-experimental-features "nix-command flakes" \
    build --no-link --print-out-paths "$source#$configuration")
  backup_extension="quickstart-backup-$(date -u +'%Y%m%dT%H%M%SZ')"
  run_logged sudo -u "$ADMIN_USER" -H env \
    PATH="/nix/var/nix/profiles/default/bin:$PATH" NIX_REMOTE=daemon \
    HOME_MANAGER_BACKUP_EXT="$backup_extension" \
    "$activation/activate" --driver-version 1
  log "activated Home Manager configuration from $source (conflict backup extension: $backup_extension)"
}

write_receipt() {
  local receipt="/var/lib/quickstart/last-bootstrap"
  local source_revision="local"

  install -d -o root -g root -m 0700 /var/lib/quickstart
  if [[ -z "$SOURCE_DIR" && -d "$INSTALL_ROOT/.git" ]]; then
    source_revision=$(sudo -u "$ADMIN_USER" -H git -C "$INSTALL_ROOT" rev-parse HEAD)
  fi

  cat >"$receipt" <<RECEIPT
completed_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
requested_ref=$QUICKSTART_REF
source_revision=$source_revision
admin_user=$ADMIN_USER
ssh_policy=key-only-root-disabled
nix_skipped=$SKIP_NIX
log_file=$LOG_FILE
rollback_dir=$ROLLBACK_DIR
RECEIPT
  chmod 0600 "$receipt"
  log "wrote receipt to $receipt"
}

main() {
  preflight
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run complete; no host changes were made"
    return 0
  fi

  acquire_bootstrap_lock
  setup_logging
  log "starting Quickstart bootstrap"
  install_prerequisites
  install_admin_account
  prepare_access_rollback
  HANDOFF_ARMED=1
  install_authorized_keys
  stage_public_key_access
  if ! wait_for_verified_login; then
    log "restoring pre-bootstrap access state after failed SSH handoff"
    if restore_staged_access; then
      HANDOFF_ARMED=0
    fi
    return 1
  fi
  activate_sshd_hardening

  if [[ "$SKIP_NIX" -eq 0 ]]; then
    install_nix
    activate_home_manager
  else
    log "skipping Nix and Home Manager by request"
  fi

  write_receipt
  log "Quickstart bootstrap completed successfully"
}

main "$@"
