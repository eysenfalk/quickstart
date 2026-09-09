# quickstart

Reproducible development and server environments: easy to run, safe to repair.

Quickstart currently provides a Debian/Ubuntu server bootstrap that:

- creates the locked-password administrator `aemon`;
- installs six pinned Ed25519 public keys exactly;
- grants explicitly configured passwordless sudo;
- waits for a real second SSH login as `aemon`;
- only then disables password, keyboard-interactive, and direct root SSH login;
- installs pinned Nix 2.34.8 and a locked Home Manager environment;
- can be re-run to converge or repair the managed state.

Read [`PLAN.md`](PLAN.md) for the product intent and architecture. Read
[`docs/threat-model.md`](docs/threat-model.md) before using the bootstrap on a
real server.

## Status

Implemented and locally validated, but **not released or deployed**. Do not run
a remote command until the reviewed commit has been pushed and pinned below.

Supported host matrix:

- Debian 12 and 13;
- Ubuntu 22.04, 24.04, and 26.04;
- `x86_64` and `aarch64`.

The SSH policy has container integration coverage on all five distributions.
A full systemd-container journey covers the login handoff, interruption
rollback, hardening, official Nix install, Home Manager activation, and re-run.
The Home Manager configuration is built on `x86_64-linux` and evaluated on
`aarch64-linux`. A disposable VM journey is still required before the first
real server deployment.

## One-command bootstrap

After a reviewed commit exists publicly, replace `<COMMIT>` with its immutable
full 40-character Git commit:

```bash
QS_REF='<COMMIT>'; QS_INSTALL=$(mktemp); trap 'rm -f "$QS_INSTALL"' EXIT; curl --proto '=https' --tlsv1.2 --fail --show-error --location "https://raw.githubusercontent.com/eysenfalk/quickstart/$QS_REF/bootstrap/install.sh" -o "$QS_INSTALL" && bash "$QS_INSTALL" --ref "$QS_REF"
```

Run this as `root` inside the provider-supplied SSH session. Keep that session
open. The installer will pause and ask you to open a second terminal with:

```bash
ssh aemon@SERVER_ADDRESS
```

It observes the new remote systemd login session automatically. If no verified
login appears within ten minutes, it restores the prior authorized-key and
staged SSH state and leaves root/password SSH policy unchanged.

Using `main` is available for development but intentionally warned as mutable:

```bash
QS_REF='main'; QS_INSTALL=$(mktemp); trap 'rm -f "$QS_INSTALL"' EXIT; curl --proto '=https' --tlsv1.2 --fail --show-error --location "https://raw.githubusercontent.com/eysenfalk/quickstart/$QS_REF/bootstrap/install.sh" -o "$QS_INSTALL" && bash "$QS_INSTALL" --ref "$QS_REF"
```

## Local checks

```bash
tests/static/run.sh
tests/container/run.sh debian:12-slim debian:13-slim ubuntu:22.04 ubuntu:24.04 ubuntu:26.04
tests/systemd/run.sh
RUN_NIX=1 tests/systemd/run.sh
```

Nix validation without installing Nix locally:

```bash
tests/nix/run.sh
```

## Documentation

- [Bootstrap behavior and options](docs/bootstrap.md)
- [Operations and updates](docs/operations.md)
- [Failure recovery](docs/recovery.md)
- [Threat model](docs/threat-model.md)
- [Secrets boundary](secrets/README.md)
