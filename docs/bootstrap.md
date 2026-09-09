# Bootstrap

## Contract

`bootstrap/install.sh` converts a supported fresh Debian/Ubuntu host from a
provider-supplied root SSH login into the managed Quickstart baseline.

It is deliberately interactive at one point: final SSH hardening waits for a
new remote `aemon` session. This preserves the one-command operator entry point
without pretending that local configuration checks prove remote access.

## Options

```text
--ref REF             full 40-character commit; main only for development
--source-dir DIR      local development checkout; no remote material download
--login-timeout SEC   30–3600 seconds; default 600
--dry-run             preflight only
--skip-nix            account and SSH baseline only
--console             allow a verified provider/recovery console instead of SSH
```

`--console` changes only the initial-session preflight. It does not bypass the
required second remote `aemon` login.

## Execution stages

1. Validate root, OS/version, architecture, systemd, SSH context, ref, and
   `flock`, then acquire the process-scoped bootstrap lock.
2. Install the minimum host prerequisites through `apt`.
3. Create or validate `aemon`, lock its password, and validate its sudoers file.
4. Validate the canonical six-key file and its separate fingerprint manifest.
5. Atomically install exact `authorized_keys` ownership and modes.
6. Stage an `aemon`-only key policy with the canonical authorized-key path and
   alternative key sources disabled, then wait for a newly observed remote
   `sshd` systemd session belonging to `aemon`.
7. Install and validate `00-quickstart.conf`, reload OpenSSH, and verify the
   effective policy for both `aemon` and `root`.
8. Download the pinned official Nix 2.34.8 installer and verify its SHA-256.
9. Install or validate exact multi-user Nix, check out the requested Quickstart
   revision as `aemon`, run `nix flake check`, build Home Manager, and activate
   the matching architecture.
10. Write a local receipt.

## Managed native files

```text
/etc/sudoers.d/90-quickstart-aemon
/etc/ssh/sshd_config.d/00-quickstart.conf
/home/aemon/.ssh/authorized_keys
/opt/quickstart/
/var/lib/quickstart/last-bootstrap
/var/lib/quickstart/rollback-*/
/var/log/quickstart/bootstrap-*.log
```

Quickstart treats `authorized_keys` and its sshd drop-in as authoritative.
Manual changes to those files are replaced on the next successful run.

## SSH proof

Immediately before waiting, the installer records all current remote systemd
session IDs for `aemon`. It continues only after `loginctl` reports a new,
non-closing, remote `sshd` session for that user with a remote address. The same
session is revalidated immediately before and after sshd reload.

The staged policy requires `AuthenticationMethods publickey`, points
`AuthorizedKeysFile` at `.ssh/authorized_keys`, and disables host-based, GSSAPI,
CA, and command-based alternatives. The observed login therefore demonstrates
the managed key path. Existing root sessions remain alive when
`PermitRootLogin no` is reloaded; the setting prevents new root logins.

## Receipts and logs

Logs and receipts are root-readable only. They record state transitions,
versions, and validation outcomes, but not environment dumps or private key
material.

The receipt is `/var/lib/quickstart/last-bootstrap`. It records the requested
ref, resolved checkout commit when available, policy state, Nix skip state, log
path, and rollback directory.

## Development run

A local checkout can exercise preflight without downloading repository files:

```bash
sudo bash bootstrap/install.sh --source-dir "$PWD" --ref main --dry-run
```

Do not run a mutating local-source invocation against a real server: a local
checkout is not an immutable release boundary.
