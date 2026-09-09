# Threat model

## Protected outcomes

Quickstart aims to preserve:

- an authenticated administrative recovery path during SSH transition;
- integrity of the `aemon` authorized-key set;
- integrity and provenance of executed bootstrap and Nix inputs;
- confidentiality of private keys, tokens, and unrelated host data;
- deterministic configuration and an inspectable audit trail.

## Trusted boundary

The first release trusts:

- Falk's local machine and matching private keys;
- the hosting provider's initial root channel and rescue console;
- GitHub availability, repository integrity, HTTPS, DNS, and CA trust;
- the pinned Quickstart Git revision;
- Debian/Ubuntu package repositories configured by the provider;
- the pinned official Nix installer and its verified SHA-256;
- pinned Nix flake inputs and the Nix binary cache trust configuration.

A commit hash and checksum provide integrity and reviewability; they do not prove
that the original author or upstream was uncompromised.

## Addressed threats

### SSH lockout

Final hardening requires a newly observed remote `aemon` systemd session.
Candidate configuration is checked with `sshd -t`; effective settings are
checked with `sshd -T`; established root sessions are not closed; failed
activation restores the previous managed drop-in.

### Password attacks

The managed account has a locked password. Final SSH policy disables password
and keyboard-interactive authentication and prohibits direct root login.

### Key drift

The canonical file contains exactly six Ed25519 public keys. A separate
fingerprint manifest is checked before installation and afterward. Installation
uses owner `aemon`, directory mode `0700`, and file mode `0600`.

### Partial writes

Keys and native configuration are staged and installed with controlled modes.
Syntax and effective policy are verified before and after reload. Rollback data
is root-only.

### Concurrent bootstrap

A root-owned lock file is held through a process-scoped `flock` file descriptor,
preventing overlapping runs without leaving a stale lock after a crash.

### Moving-source execution

The production command pins a full Git commit and passes that same revision to
every fetched repository artifact and checkout. Movable tags are rejected. Use
of `main` emits an explicit warning.

### Secret disclosure

No private key or token is required by the public bootstrap. Logs avoid
environment dumps. Future secrets must use encrypted values or external
references.

## Accepted risks

- `NOPASSWD` sudo means compromise of `aemon` is immediate root compromise.
- The six approved public keys have equal administrative power; compromise of
  any corresponding private key compromises the server.
- A real SSH login proves the access path worked at that moment, not that every
  approved key works.
- The login proof depends on systemd-logind accurately marking a new session as
  remote.
- Existing root sessions remain privileged until closed by the operator.
- HTTPS and a pinned Git ref do not provide offline signature verification of
  the initial bootstrap file.
- Distribution packages and the provider image remain outside Nix's lockfile.
- No host firewall is configured in the first release.

## Out of scope

The first release does not defend against:

- a malicious hosting provider, firmware, kernel, or already-compromised image;
- theft of Falk's local private keys;
- malicious code already present in an approved Quickstart or upstream commit;
- denial of service by GitHub, package mirrors, DNS, or the provider;
- application vulnerabilities in services installed later;
- loss of persistent data not covered by an independent backup system.

## Review triggers

Repeat threat review when:

- adding a new public key or administrator;
- changing sudo policy;
- changing SSH authentication methods or ports;
- adding a firewall;
- changing Nix installer or cache trust;
- adding secrets;
- making the repository private;
- adding unattended execution;
- supporting another distribution or init system;
- deploying AI agents with write or production access.
