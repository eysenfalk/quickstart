# Operations

## Re-applying a release

Run the same release-pinned bootstrap command again. The installer converges the
account, exact key set, sudo policy, SSH policy, repository checkout, Nix
installation, and Home Manager generation.

A re-run still requires a new second `aemon` SSH session before it reloads the
final SSH policy. This deliberately re-proves the access path during repair.

## Updating Quickstart

1. Change configuration in a development checkout.
2. Run static, container, Nix, and systemd integration checks.
3. Update Nix inputs only deliberately:

   ```bash
   nix flake update
   nix flake check
   ```

4. Review `flake.lock` and the complete diff.
5. Run the disposable systemd VM journey.
6. Commit and push the reviewed revision.
7. Create a release tag if desired.
8. use a command whose `--ref` matches that immutable revision.

Never change `flake.lock` implicitly during bootstrap.

## Home Manager operations

Build without activating:

```bash
nix build '.#homeConfigurations."aemon@x86_64-linux".activationPackage'
```

On ARM64, replace the system suffix with `aarch64-linux`.

List generations as `aemon`:

```bash
home-manager generations
```

Rollback as `aemon`:

```bash
home-manager switch --rollback
```

## Audit

Host-level evidence:

```bash
sudo cat /var/lib/quickstart/last-bootstrap
sudo sshd -t
sudo sshd -T -C user=aemon,host="$(hostname -f)",addr=127.0.0.1 \
  | grep -E '^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|authenticationmethods|gssapiauthentication|hostbasedauthentication|authorizedkeysfile|authorizedkeyscommand|trustedusercakeys) '
sudo visudo -c
sudo ssh-keygen -lf /home/aemon/.ssh/authorized_keys
```

Expected effective values:

```text
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin no
authenticationmethods publickey
gssapiauthentication no
hostbasedauthentication no
authorizedkeysfile .ssh/authorized_keys
authorizedkeyscommand none
trustedusercakeys none
```

## Tests

Static checks require Bash, ShellCheck, OpenSSH client tools, and Git:

```bash
tests/static/run.sh
```

Container checks require Docker and exercise real OpenSSH public-key login,
passwordless sudo, effective policy, and root denial:

```bash
tests/container/run.sh debian:12-slim debian:13-slim ubuntu:22.04 ubuntu:24.04 ubuntu:26.04
```

Nix evaluation/build and formatting run without a host Nix installation:

```bash
tests/nix/run.sh
```

The privileged systemd container test exercises real `loginctl` SSH sessions,
service reload, interruption rollback, first run, and re-run. Its optional full
mode additionally installs official Nix and activates Home Manager:

```bash
tests/systemd/run.sh
RUN_NIX=1 tests/systemd/run.sh
```

This provides a strong local integration gate but does not replace the final
disposable VM run: the systemd container still shares the host kernel and its
network/storage boundary differs from a provider VM.
