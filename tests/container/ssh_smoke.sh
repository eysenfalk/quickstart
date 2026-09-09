#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update >/dev/null
apt-get install -y --no-install-recommends openssh-client openssh-server sudo >/dev/null

# shellcheck source=bootstrap/lib/core.sh
source /repo/bootstrap/lib/core.sh

adduser --disabled-password --gecos "" --home /home/aemon --shell /bin/bash aemon >/dev/null
passwd --lock aemon >/dev/null
usermod --append --groups sudo aemon

printf '%s\n' 'aemon ALL=(ALL:ALL) NOPASSWD: ALL' >/etc/sudoers.d/90-quickstart-aemon
chmod 0440 /etc/sudoers.d/90-quickstart-aemon
visudo -c >/dev/null

ssh-keygen -q -t ed25519 -N '' -f /tmp/client-key
install -d -o aemon -g aemon -m 0700 /home/aemon/.ssh
install -o aemon -g aemon -m 0600 /tmp/client-key.pub /home/aemon/.ssh/authorized_keys
install -d -o root -g root -m 0700 /root/.ssh
install -o root -g root -m 0600 /tmp/client-key.pub /root/.ssh/authorized_keys

install -d -m 0755 /etc/ssh/sshd_config.d /run/sshd
ssh-keygen -A >/dev/null

install -m 0644 /repo/ssh/sshd-stage.conf /etc/ssh/sshd_config.d/00-quickstart-stage.conf
/usr/sbin/sshd -t
/usr/sbin/sshd -T -C user=aemon,host=localhost,addr=127.0.0.1 >/tmp/staged-aemon
/usr/sbin/sshd -T -C user=root,host=localhost,addr=127.0.0.1 >/tmp/staged-root
qs_assert_key_source_policy /tmp/staged-aemon
[[ "$(qs_effective_value /tmp/staged-aemon passwordauthentication)" == "no" ]]
[[ "$(qs_effective_value /tmp/staged-root passwordauthentication)" == "yes" ]]
[[ "$(qs_effective_value /tmp/staged-root authenticationmethods)" == "any" ]]
rm -f /etc/ssh/sshd_config.d/00-quickstart-stage.conf

install -m 0644 /repo/ssh/sshd-hardening.conf /etc/ssh/sshd_config.d/00-quickstart.conf
/usr/sbin/sshd -t
/usr/sbin/sshd -T -C user=aemon,host=localhost,addr=127.0.0.1 >/tmp/effective-aemon
/usr/sbin/sshd -T -C user=root,host=localhost,addr=127.0.0.1 >/tmp/effective-root
qs_assert_effective_policy /tmp/effective-aemon
qs_assert_effective_policy /tmp/effective-root

# A rerun temporarily has both files present; staging must not scope the final
# global policy to aemon or weaken root authentication.
install -m 0644 /repo/ssh/sshd-stage.conf /etc/ssh/sshd_config.d/00-quickstart-stage.conf
/usr/sbin/sshd -t
/usr/sbin/sshd -T -C user=aemon,host=localhost,addr=127.0.0.1 >/tmp/rerun-aemon
/usr/sbin/sshd -T -C user=root,host=localhost,addr=127.0.0.1 >/tmp/rerun-root
qs_assert_effective_policy /tmp/rerun-aemon
qs_assert_effective_policy /tmp/rerun-root
rm -f /etc/ssh/sshd_config.d/00-quickstart-stage.conf

/usr/sbin/sshd -D -e -p 2222 >/tmp/sshd.log 2>&1 &
sshd_pid=$!
trap 'kill "$sshd_pid" 2>/dev/null || true' EXIT

ssh_options=(
  -o BatchMode=yes
  -o ConnectTimeout=2
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o PasswordAuthentication=no
  -i /tmp/client-key
  -p 2222
)

connected=0
for _ in $(seq 1 20); do
  if ssh "${ssh_options[@]}" aemon@127.0.0.1 true 2>/dev/null; then
    connected=1
    break
  fi
  sleep 0.25
done
[[ "$connected" -eq 1 ]] || {
  printf 'aemon public-key login failed\n' >&2
  cat /tmp/sshd.log >&2
  exit 1
}

if ssh "${ssh_options[@]}" root@127.0.0.1 true >/dev/null 2>&1; then
  printf 'root SSH login unexpectedly succeeded\n' >&2
  exit 1
fi

sudo -u aemon sudo -n true
printf 'PASS: SSH key login, sudo, effective policy, and root denial\n'
