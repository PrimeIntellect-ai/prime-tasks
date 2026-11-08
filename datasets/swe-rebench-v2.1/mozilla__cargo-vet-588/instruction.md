prefer local wildcard audits to remote regular audits
Over on [mozilla-central](https://phabricator.services.mozilla.com/D197955), @jrmuizel and @glandium identified an interesting issue where Jeff was trying to replace a regular audit with a wildcard audit. Rather than reifying the local wildcard audit, cargo-vet instead re-fetches the locally-deleted regular audit from the [aggregated mozilla-wide set](https://raw.githubusercontent.com/mozilla/supply-chain/main/audits.toml) and re-inserts it as an import.

[HIDDEN]

@afranchuk Is my hypothesis correct?

### Additional contract requirements

- When a local wildcard audit and a remote regular audit could both account for the same crate, prefer the local wildcard audit; do not add a fresh remote regular audit solely to satisfy that need.
- When pruning import-file changes, retain an already-existing imported regular audit even if a local wildcard audit accounts for the crate.
