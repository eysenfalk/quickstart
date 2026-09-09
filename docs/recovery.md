# Recovery

## Safety rule

Keep the original provider root session open until all checks complete and at
least one later `aemon` maintenance session has succeeded. Know how to enter the
provider rescue console before the first deployment.

## Second login times out

Quickstart does not activate final SSH hardening. It restores the previous
`authorized_keys` state and removes its temporary SSH staging drop-in.

From the still-open root session:

```bash
journalctl -u ssh --since '-15 minutes'
sshd -t
sshd -T -C user=aemon,host="$(hostname -f)",addr=127.0.0.1 \
  | grep -E '^(pubkeyauthentication|authorizedkeysfile|usepam) '
namei -l /home/aemon/.ssh/authorized_keys
ssh-keygen -lf /home/aemon/.ssh/authorized_keys
```

Correct the underlying problem rather than enabling loose permissions or broad
password authentication. Then re-run the same pinned bootstrap command.

## sshd validation or reload fails

The installer restores the previous managed drop-in when final activation
fails. Inspect:

```bash
sshd -t
systemctl status ssh.service --no-pager
journalctl -u ssh --since '-15 minutes'
ls -la /etc/ssh/sshd_config.d/
```

Debian/Ubuntu normally use `ssh.service`; the installer also detects
`sshd.service`.

If manual restoration is required, use the rollback directory printed in the
log or receipt:

```bash
cat /var/lib/quickstart/last-bootstrap
ls -la /var/lib/quickstart/rollback-*/
```

Validate with `sshd -t` before any reload. Prefer `systemctl reload ssh` over a
restart so established sessions survive.

## `aemon` sudo is broken

From the preserved root session or provider console:

```bash
visudo -cf /etc/sudoers.d/90-quickstart-aemon
id aemon
passwd -S aemon
```

The intended first-release policy is:

```text
aemon ALL=(ALL:ALL) NOPASSWD: ALL
```

The account password remains locked. Do not unlock it merely to repair sudo.

## Nix or Home Manager fails

SSH hardening and account setup are separate earlier boundaries. A Nix failure
must not roll them back after the verified handoff.

Inspect the root-readable Quickstart log. Verify:

```bash
systemctl status nix-daemon.service --no-pager
/nix/var/nix/profiles/default/bin/nix --version
sudo -u aemon -H /nix/var/nix/profiles/default/bin/nix \
  --extra-experimental-features 'nix-command flakes' flake check /opt/quickstart
```

Home Manager generations can be rolled back independently as `aemon`.

## Complete network lockout

Use the hosting provider's rescue console. Quickstart cannot recover failures
in provider firewalls, networking, routing, boot, storage, or host keys through
an unavailable SSH channel.

From the console:

1. inspect `/etc/ssh/sshd_config` and its drop-ins;
2. restore a known-valid managed file from `/var/lib/quickstart/rollback-*`;
3. run `sshd -t`;
4. reload or start the correct SSH service;
5. verify provider and host firewall rules;
6. reconnect before closing the console.
