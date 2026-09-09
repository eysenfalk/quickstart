# Quickstart: Foundation and Server Bootstrap Plan

Status: milestones 1–4 implemented locally; not released or deployed
Initial platform: Debian and Ubuntu servers
Canonical administrative user: `aemon`
Repository: `eysenfalk/quickstart`

## Essence

Quickstart is the reproducible source of truth for Falk's development and server environments.

A fresh server with only a root SSH login, Bash, and either `curl` or `wget` must be able to reach a secure, maintainable baseline from one command. The same repository must also be able to repair drift on an existing machine and, over time, reproduce development workstations and AI-agent environments.

The essence is not “a large installation script.” It is:

> One small bootstrap entry point activates a versioned, declarative system definition.

## Intention

Quickstart will make machine setup deliberate instead of archaeological.

It will:

- turn a newly provisioned Debian or Ubuntu server into a usable baseline;
- create the `aemon` administrator account;
- install the approved SSH public keys idempotently;
- prove that a second SSH session as `aemon` works before disabling risky login paths;
- permit SSH authentication only by public key after the transition;
- disable direct root SSH login after the verified handoff;
- install and activate the reproducible user environment;
- distinguish configuration from secrets, persistent data, caches, and backups;
- support safe re-runs for updates and repair;
- make every consequential change inspectable in Git.

The operator experience remains one initial command. That command may pause and ask the operator to open a second SSH session as `aemon`; this is a safety handshake, not a second installation command.

## Premise

### Starting state

The first supported machine is assumed to have:

- Debian or Ubuntu;
- a working `root` SSH session authenticated with the provider's temporary password;
- Bash;
- `curl` or `wget`;
- a running OpenSSH server;
- working DNS and outbound HTTPS;
- a functional distribution package manager;
- systemd for the first implementation.

No GitHub credentials, private SSH keys, password manager, Nix installation, or pre-existing `aemon` account may be assumed.

The bootstrap must detect the actual state and fail closed when a required premise is false. Unsupported distributions must receive a clear error; they must not be treated as “probably compatible.”

### Security premise

The initial root password is temporary and unsafe as a long-term administration mechanism. Public-key access for an unprivileged named administrator must be established before it is removed.

A process running on the server cannot prove by itself that Falk possesses a matching private key on a separate machine or that the network path works. Local checks such as `sshd -t` are necessary but insufficient. Therefore the bootstrap requires a real second SSH login by `aemon` before final hardening.

The existing root session remains open during the handoff. If the second login does not occur before the timeout, the bootstrap exits without disabling the existing root login.

### Reproducibility premise

There are four distinct classes of state:

1. **Declared configuration** — packages, services, users, dotfiles, agent instructions, and policies. This belongs in this repository.
2. **Secret material** — tokens, private keys, password hashes, recovery credentials. Only encrypted values or external secret references may be committed.
3. **Persistent personal/application data** — repositories, databases, documents, conversations, browser profiles. This belongs in a backup system, not in Quickstart.
4. **Ephemeral state** — caches, build outputs, downloaded artifacts, sessions. This should normally be recreated rather than migrated.

Reproducible does not mean byte-identical hardware, firmware, SaaS accounts, or mutable third-party services. The repository guarantees the declared state within a documented platform and version boundary.

### Current repository state

The repository began with only `README.md`. Milestones 1–4 now add the bootstrap, canonical access policy, tests, locked Nix/Home Manager baseline, and operations documentation. There was no legacy setup to preserve or migrate.

The GitHub repository is publicly readable, which allows a credential-free bootstrap. Making future repository content private would require a different authenticated bootstrap channel.

## Vision

A new server is commissioned as follows:

1. Falk copies one release-pinned command from the repository documentation.
2. He runs it in the provider-supplied root SSH session.
3. Quickstart performs preflight checks, creates `aemon`, and installs the approved public keys.
4. Quickstart waits while Falk opens a second terminal and logs in as `aemon` using one of those keys.
5. Once that real session is detected, Quickstart validates and activates key-only SSH policy and disables root SSH login.
6. It installs the declarative environment and activates the selected server profile.
7. It prints a concise receipt: release, host, applied profile, checks, changed files, and any remaining manual actions.

The same command can later be re-run. Already-correct state is reported as unchanged; drift is repaired; version changes are explicit; errors do not leave partially written security configuration.

Eventually the same model supports:

- minimal servers;
- development servers;
- Linux workstations;
- macOS through a separate host adapter;
- personal Pi and other AI-agent environments;
- fresh installation, update, repair, audit, and rollback.

## Purpose

Quickstart exists to reduce five risks:

1. **Recovery risk:** a failed machine must not require memory or improvisation to rebuild.
2. **Configuration drift:** current reality and intended reality must be comparable.
3. **Access risk:** SSH hardening must not accidentally lock out the legitimate operator.
4. **Supply-chain risk:** root must not execute an unversioned moving script without a defined trust boundary.
5. **Agent drift:** AI-agent instructions, skills, integrations, and tool versions must be reproducible without copying credentials or private runtime history.

Success is not measured by how much configuration the repository contains. It is measured by whether a fresh supported machine can be brought to the intended state safely, repeatedly, and observably.

## Strategy

### 1. Architectural boundaries

Quickstart will use a layered architecture with one owner per resource.

#### Bootstrap layer

A small, conservative Bash program owns only the transition from an unknown fresh host to the managed baseline. It may:

- perform platform and privilege checks;
- install minimum host prerequisites through `apt`;
- create the administrative user and sudo policy;
- install SSH public keys;
- stage, validate, and activate SSH hardening;
- install Nix in supported multi-user mode;
- fetch a pinned Quickstart revision;
- invoke the declarative configuration;
- emit logs and an installation receipt.

It must not grow into the long-term package or dotfile manager.

#### Native host layer

On Debian and Ubuntu, the distribution remains responsible for boot-critical and security-critical host components, initially including:

- OpenSSH server;
- `sudo`;
- CA certificates;
- the package manager itself;
- systemd;
- kernel and bootloader;
- provider networking.

Quickstart configures these components but does not replace them with Nix packages on the first iteration.

#### Declarative user layer

Nix Flakes and standalone Home Manager will own the reproducible `aemon` userspace:

- CLI packages;
- shell configuration;
- Git configuration;
- editor and terminal configuration;
- user-level environment variables;
- user services where suitable;
- development and AI-agent tooling;
- profile composition.

`flake.lock` is committed. Inputs change only through explicit update work, followed by checks.

#### Future system layer

NixOS may later become the system-level target for machines where full operating-system reproducibility is worth controlling the image. It is not required to bootstrap the first existing Debian/Ubuntu server.

macOS will later use `nix-darwin` and, only where necessary, Homebrew for native applications. Windows-native support is outside the initial scope; WSL may consume the Linux user profile later.

### 2. Proposed repository shape

```text
quickstart/
├── README.md
├── PLAN.md
├── flake.nix
├── flake.lock
├── bootstrap/
│   ├── install.sh
│   └── lib/
├── hosts/
│   └── <host>/
│       ├── default.nix
│       └── facts.nix
├── profiles/
│   ├── common.nix
│   ├── server-base.nix
│   ├── development.nix
│   └── ai.nix
├── home/
│   └── aemon.nix
├── modules/
│   ├── shell/
│   ├── git/
│   ├── editors/
│   └── tools/
├── users/
│   └── aemon/
│       └── authorized_keys
├── ssh/
│   └── sshd-hardening.conf
├── agents/
│   ├── instructions/
│   ├── skills/
│   ├── mcp/
│   └── vendors/
├── secrets/
│   └── README.md
├── tests/
│   ├── static/
│   └── vm/
└── docs/
    ├── bootstrap.md
    ├── operations.md
    ├── recovery.md
    └── threat-model.md
```

Host files express facts and selected profiles. Reusable behavior lives in modules and profiles. Hostnames must not become copies of complete configurations.

### 3. One-command contract

The final documented command will have this shape, but it must not be published as runnable until the script and release exist:

```bash
QS_REF='<full-commit>'; QS_INSTALL=$(mktemp); trap 'rm -f "$QS_INSTALL"' EXIT; \
  curl --proto '=https' --tlsv1.2 --fail --show-error --location \
  "https://raw.githubusercontent.com/eysenfalk/quickstart/$QS_REF/bootstrap/install.sh" \
  -o "$QS_INSTALL" && bash "$QS_INSTALL" --ref "$QS_REF"
```

This is one shell command; `mktemp` creates the root-owned temporary file and
the downloaded file is not executed if the transfer fails.

Rules:

- `<full-commit>` is a reviewed full 40-character Git commit; movable tags and `main` are rejected or discouraged for production.
- The README may additionally expose a clearly labelled “latest” convenience command, but it is not the reproducible or safest path.
- Redirects are followed only over HTTPS; TLS 1.2 or newer is required where `curl` supports it.
- The installer records its source revision.
- The bootstrap URL contains no token, password, private key, or machine secret.
- A future signed-release mechanism may strengthen provenance, but it must not be claimed before a verifier and key-distribution path exist.
- Executing any remotely downloaded program as root remains a trust decision. The pinned revision makes the reviewed input inspectable and immutable; it does not eliminate trust in GitHub, TLS, or the repository maintainers.

If only `wget` exists, the documented entry point may use a separate equivalent command. The script itself must not recursively pipe opaque content into another shell.

### 4. Bootstrap execution plan

#### Phase A — preflight

Before mutation, the installer will:

1. enable strict Bash behavior and a predictable `PATH`;
2. require effective UID 0;
3. acquire an exclusive lock so two runs cannot overlap;
4. parse `/etc/os-release` and accept only tested Debian/Ubuntu releases;
5. require systemd and identify the actual SSH service unit;
6. verify that the current process is associated with a remote SSH session, unless an explicit console-recovery mode is selected;
7. verify writable filesystem space, DNS, clock sanity, and HTTPS connectivity;
8. inventory relevant existing state without reading or printing private key material;
9. create a restricted root-owned log with secret redaction;
10. establish rollback copies for every native configuration file it may replace.

A failed preflight performs no security-policy change.

#### Phase B — minimum host prerequisites

Using noninteractive `apt`, the installer will ensure the tested minimum set, expected to include:

- `ca-certificates`;
- `curl`;
- `git`;
- `openssh-server`;
- `sudo`;
- `xz-utils` and other prerequisites required by the selected Nix installer.

The exact list is decided from implementation tests, not guessed into permanence. Package installation must use distribution package names and report whether a reboot is required.

Unattended full-distribution upgrades are outside bootstrap. They can restart networking or SSH and make failure attribution unsafe. Update policy will be a separate managed operation.

#### Phase C — `aemon` account

The installer will converge the following state:

- user name: `aemon`;
- normal home directory: `/home/aemon`;
- interactive Bash login shell initially;
- locked password, so the account cannot use password authentication;
- administrative access through a validated `/etc/sudoers.d/` drop-in;
- home and SSH directory owned by `aemon`;
- `~/.ssh` mode `0700`;
- `authorized_keys` mode `0600`;
- no private key generated or copied to the server.

Because the account has no usable password, the initial plan is explicit `NOPASSWD` sudo for `aemon`. This is convenient and consistent with key-only administration, but it means compromise of the account immediately grants root. The implementation review must either deliberately approve this policy or replace it with an enrolled second factor or separately delivered password hash. It must not accidentally inherit an unusable “sudo requires a locked password” state.

The sudoers fragment is written atomically and validated with `visudo -c` before installation.

#### Phase D — authorized keys

The canonical key set will live at `users/aemon/authorized_keys` and contain the six public keys approved by Falk. The installer will:

- parse and validate every line before changing the target file;
- accept only the intended public-key algorithms in the first version;
- reject blank key bodies, private-key markers, shell expansions, and malformed lines;
- deduplicate by algorithm plus public-key blob, not by comment;
- write a temporary file, set ownership and modes, and atomically rename it;
- verify the installed fingerprints against the release manifest;
- treat the repository file as authoritative for this managed account.

Whether unknown pre-existing keys are removed is a security-sensitive policy. For a fresh or explicitly managed `aemon` account, the intended behavior is exact convergence: keys absent from the repository are removed after the handoff. Before the handoff, the previous file is retained in the rollback area.

Approved key fingerprints:

| Fingerprint | Comment |
|---|---|
| `SHA256:VgS3/yQ7j7qxsZANvogV/spINwjKTn4Z3Aalv/naVtU` | none |
| `SHA256:3Rw7+AJxkrh2fXy7R0dIS/Z1j8SrBVXFbh0kO7WykaQ` | `eysen@godmachine` |
| `SHA256:U6jG9fJ6p+vFaTb0cmUA9ykQVNgonmHT53BaByQ/ODs` | `feysen` |
| `SHA256:LB7MOOFNheuVFO/U5NwCkopFIHG6nBIBTI/tK9tCS7c` | none |
| `SHA256:LQXX1GivipD2GjBSN6ljOLNahLjulPYzo75/uF2ScgA` | `moshi` |
| `SHA256:udGu036VciiuO83aton0QAblt40PklK8fhG+bkuX8dI` | `falk@godhunter` |

The full public-key lines are implementation data, not secrets. They are committed in the canonical key file.

#### Phase E — staged SSH handoff

SSH changes use a two-stage state machine.

**Stage 1: establish the replacement path**

1. Confirm that `aemon` has a locked password and valid authorized keys.
2. Confirm from the effective sshd configuration that public-key authentication is available for `aemon`.
3. Validate all candidate SSH configuration with the target host's own `sshd -t`.
4. Reload rather than restart SSH where supported, preserving the current root session.
5. Display the exact second-session command, for example `ssh aemon@<detected-address>`.
6. Wait for a new remote `aemon` session with a bounded timeout.

Because `aemon` has no valid password, a successful normal SSH login proves that a non-password authentication path was used. The implementation must use reliable session evidence available on the tested systems and must log what it accepted as proof. Merely pressing Enter in the root session is not proof.

If the timeout expires or proof is ambiguous, the run stops before final hardening. Re-running resumes safely.

**Stage 2: activate final policy**

After the verified second login, Quickstart converges an OpenSSH policy equivalent to:

- public-key authentication enabled;
- password authentication disabled;
- keyboard-interactive/challenge-response authentication disabled;
- direct root SSH login disabled;
- PAM session/account handling retained where required by Debian/Ubuntu;
- no weakening of host-key or cryptographic defaults without a separately reviewed reason.

The implementation will use a managed sshd drop-in when the target package's include order makes that authoritative. OpenSSH commonly applies the first obtained value for a keyword, so filename order alone must not be assumed. The installer must inspect `sshd -T` effective output for relevant connection contexts and refuse activation if another file or `Match` block defeats the intended policy.

Before reload:

- candidate files are syntactically validated with `sshd -t`;
- effective settings are checked with `sshd -T` and an appropriate connection context;
- rollback data exists;
- the verified `aemon` session remains open.

After reload, effective settings are checked again. A failure restores the previous managed configuration and reloads the last known-valid state. Existing SSH sessions are never intentionally terminated by the bootstrap.

Firewall changes are not bundled into this first SSH transition. Provider firewalls and host firewalls require explicit port and network requirements; guessing them can cause lockout.

#### Phase F — Nix and Home Manager

Once durable `aemon` administration exists, Quickstart will:

1. install Nix in tested multi-user/daemon mode using a versioned installer decision;
2. verify the daemon, store ownership, and profile initialization;
3. check out the same pinned Quickstart revision used by the bootstrap;
4. build the selected Home Manager configuration before activation;
5. activate the `server-base` profile for `aemon`;
6. record the resulting generation and rollback command;
7. run post-activation checks as `aemon`.

Nix installation is itself part of the supply chain. The implementation phase must choose and pin either the official Nix installer or another reviewed installer; it may not silently choose whichever endpoint currently works.

The base server profile should start small:

- shell and prompt prerequisites;
- Git;
- editor;
- terminal utilities used for diagnosis;
- process and network inspection tools;
- repository checkout conventions;
- agent prerequisites only after their ownership is defined.

Every added package needs a reason. A snapshot of everything installed on an old machine is inventory evidence, not automatically desired state.

#### Phase G — receipt

Every run produces a concise terminal result and a root-readable local receipt containing:

- Quickstart release and Git commit;
- start and finish timestamps;
- detected OS and architecture;
- selected host and profiles;
- whether the account, keys, SSH policy, Nix, and Home Manager changed;
- fingerprints of installed public keys;
- validation commands and outcomes;
- Home Manager generation;
- rollback location or command;
- pending reboot or manual decisions.

Logs must never contain environment dumps, private key material, access tokens, or unredacted secret-manager output.

### 5. Idempotency and repair

The bootstrap is a converger, not a one-shot installer.

Each operation must be one of:

- already correct — report and continue;
- safely converged — change atomically and verify;
- incompatible — stop with an actionable explanation;
- failed — roll back the current transactional boundary and stop.

Required re-run behavior:

- an existing correct `aemon` account is reused;
- duplicate SSH keys are not appended;
- removed canonical keys do not persist unnoticed;
- the sshd drop-in has deterministic content;
- Nix is not reinstalled when healthy;
- the locked repository revision is not replaced by an accidental moving branch;
- Home Manager reports whether a new generation was produced;
- interrupted runs can resume from observed state rather than trusting a stale marker.

There is no global transaction across `apt`, account creation, sshd, Nix, and Home Manager. The design therefore uses explicit transactional boundaries and guarantees access safety before package-environment completeness.

### 6. Secrets strategy

No secret is required for the first public bootstrap beyond the temporary root login already held by the operator.

Rules for later phases:

- SSH private keys never enter this repository.
- Public keys may be committed.
- API keys and agent tokens are referenced by name and injected at runtime.
- SOPS with age recipients or a reviewed password-manager integration will be selected before the first encrypted secret is committed.
- Decryption identities are provisioned out of band or derived from an explicitly approved host identity; they are not downloaded from the same public repository.
- Secret rotation must not require rewriting unrelated configuration.
- Bootstrap logs and CI use synthetic secrets only.

### 7. AI-agent strategy

The AI environment is a profile, not an opaque copy of `~/.config`.

The portable source of truth will separate:

- project guidance based on `AGENTS.md`;
- reusable Agent Skills with `SKILL.md`;
- MCP server declarations with environment-variable or secret-manager references;
- agent roles and workflows;
- pinned extension/plugin/package versions where the tool supports them;
- vendor adapters for Pi, Codex, Claude Code, Cursor, and other selected clients.

Vendor adapters may generate or link files into tool-specific locations. They must not duplicate the canonical instructions by hand. Authentication databases, OAuth sessions, conversation history, caches, machine-local telemetry, and private memories are excluded.

Before migrating the active personal Pi harness, a separate inventory and ownership review is required. The active harness must not be mutated as a side effect of developing Quickstart; candidate configuration is tested in isolation first.

### 8. Implementation sequence

Implementation began after Falk approved this plan. Deployment and publication remain separate actions.

#### Milestone 1 — contract and static data

- finalize supported Debian/Ubuntu releases and architectures;
- commit the canonical six-key file;
- define release metadata and host/profile schema;
- write the threat model and recovery contract;
- add shell formatting and static-analysis checks.

Exit criterion: schemas and security invariants are reviewable; no remote host is changed.

#### Milestone 2 — local bootstrap core

- implement strict preflight and logging;
- implement account and key convergence;
- implement sudoers validation;
- implement staged SSH configuration and rollback;
- provide a non-mutating dry-run/audit mode where technically meaningful.

Exit criterion: automated tests cover first run, re-run, malformed keys, conflicting sshd configuration, timeout, and rollback.

#### Milestone 3 — disposable VM validation

Test clean supported images, initially at least one current Debian and one Ubuntu LTS image.

Scenarios:

- fresh root-password-like starting state;
- only `curl` available;
- only `wget` available;
- existing correct `aemon` user;
- wrong ownership/modes;
- duplicate and stale keys;
- interrupted run at each transactional boundary;
- conflicting sshd drop-ins and `Match` blocks;
- failed sshd validation;
- failed reload;
- no second login before timeout;
- successful second public-key login;
- complete re-run with no unintended changes.

The test harness must prove that root/password login is not disabled before the second-login gate and that final effective sshd policy matches the contract afterward.

Exit criterion: a disposable VM can be destroyed and recreated from the documented one-command flow, and the second run is clean.

#### Milestone 4 — Nix baseline

- add `flake.nix` and committed lockfile;
- add standalone Home Manager for `aemon`;
- define `common` and `server-base` profiles;
- integrate versioned Nix installation;
- test build, activation, generation, and rollback.

Exit criterion: VM bootstrap reaches the declared user environment from the same pinned release.

#### Milestone 5 — first real server

- record non-secret host facts;
- verify provider console/recovery access before changing SSH;
- run the pinned release command in the existing root session;
- complete the second-session handoff;
- preserve the receipt and manually review effective SSH state;
- keep provider recovery credentials until a later successful maintenance session.

Exit criterion: `aemon` key login and administrative escalation work, root/password SSH login is rejected, expected profiles are active, and a re-run is clean.

#### Milestone 6 — broader environment

Migrate incrementally:

1. shell, Git, and editor;
2. development tools;
3. server services with explicit data/backup plans;
4. secrets;
5. AI-agent portable core;
6. isolated Pi/vendor adapters;
7. optional NixOS and macOS hosts.

Each migration assigns exactly one owner to every target file or service.

### 9. Validation gates

No release is ready unless all applicable gates pass:

- shell parser and formatter;
- ShellCheck or equivalent static analysis;
- key parser and fingerprint tests;
- sudoers validation through `visudo -c`;
- sshd syntax validation through the target image's `sshd -t`;
- effective-policy checks through the target image's `sshd -T`;
- Nix evaluation and `nix flake check` once the flake exists;
- Home Manager build without activation;
- disposable-VM first-run test;
- disposable-VM idempotent second-run test;
- negative authentication tests after handoff;
- rollback/failure-injection tests;
- review of the exact release-pinned bootstrap command.

Static checks alone cannot approve SSH changes. At least one realistic VM journey is mandatory before the first real server.

### 10. Failure and recovery policy

Priority order during failure:

1. preserve an authenticated administrative path;
2. preserve a valid sshd configuration;
3. restore the last known-valid native configuration;
4. stop further mutation;
5. report exact recovery steps;
6. only then clean temporary artifacts.

The installer must never respond to a failed second login by weakening file permissions, enabling broad password authentication, or accepting an unvalidated key.

Before the first real-server run, Falk must identify the hosting provider's rescue console or recovery mode. This is the final recovery boundary for network, firewall, provider, and boot failures outside Quickstart's control.

### 11. Explicit non-goals for the first release

The first release will not:

- support every Linux distribution;
- perform a distribution upgrade;
- replace Debian/Ubuntu with NixOS;
- configure an application firewall without known service requirements;
- migrate databases or personal data;
- copy private SSH keys;
- restore browser or agent session state;
- install every package found on an existing machine;
- modify the active Pi harness during development;
- publish, deploy, or run against the real server without a separate explicit action and approval.

### 12. Decisions already made

- Debian 12/13 and Ubuntu 22.04/24.04/26.04 are the initial host matrix.
- `x86_64` and `aarch64` are the initial architectures.
- The managed administrator is `aemon` with a locked password and explicit `NOPASSWD` sudo.
- Six supplied Ed25519 public keys form the exact authoritative key set.
- The operator starts with one command.
- A new remote `aemon` systemd-logind session must appear within 600 seconds before final hardening.
- Final SSH policy is public-key only and prohibits direct root SSH login.
- Nix 2.34.8 uses the pinned official installer with an independently recorded SHA-256.
- Nixpkgs and Home Manager track locked release-26.05 inputs.
- Container SSH tests cover every supported distribution; a systemd VM gate remains mandatory before the real server.

### 13. Decisions remaining for later milestones

- host naming and profile selection beyond the initial `server-base` profile;
- release signing beyond pinned Git revision, installer checksum, and HTTPS;
- SOPS/age versus an external password manager when secrets are introduced;
- application firewall policy once actual service requirements are known;
- the portable AI-agent inventory and vendor-adapter boundaries.

These remain deliberate gates for the milestones that introduce them.

## Primary references

- OpenSSH server configuration: <https://man.openbsd.org/OpenBSD-current/man5/sshd_config.5>
- OpenSSH daemon validation (`sshd -t`): <https://man.openbsd.org/OpenBSD-current/man8/sshd.8>
- Debian `adduser`: <https://manpages.debian.org/bookworm/adduser/adduser.8.en.html>
- Debian `authorized_keys`: <https://manpages.debian.org/testing/openssh-server/authorized_keys.5.en.html>
- Debian `visudo`: <https://manpages.debian.org/bookworm/sudo/visudo.8.en.html>
- Nix installation: <https://nix.dev/manual/nix/stable/installation/>
- Home Manager: <https://nix-community.github.io/home-manager/>
- AGENTS.md: <https://agents.md/>
- Agent Skills specification: <https://agentskills.io/specification>
- Model Context Protocol: <https://modelcontextprotocol.io/docs/getting-started/intro>
