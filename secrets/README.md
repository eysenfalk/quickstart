# Secrets boundary

This directory contains documentation and, later, encrypted secret declarations
only.

Allowed:

- SOPS-encrypted files whose recipients are reviewed;
- public age recipients;
- password-manager item references;
- environment-variable names;
- schemas and synthetic test values.

Forbidden:

- SSH private keys;
- plaintext API keys, tokens, passwords, recovery codes, or cookie databases;
- OAuth sessions;
- decrypted output;
- complete environment dumps;
- personal or agent conversation history.

No secret backend has been selected yet. SOPS/age versus an external password
manager remains a later explicit decision. The first server bootstrap requires
no committed secret.
