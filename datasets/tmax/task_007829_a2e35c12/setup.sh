#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip patch
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/Cargo.toml
[package]
name = "legacy_rust_app"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.0.0"
tokio = "1.8.0"
reqwest = "0.11.0"
EOF

cat << 'EOF' > /home/user/build_errors.log
[ERROR] Compilation failed due to dependency conflicts.
Some other irrelevant log lines here...

-- BEGIN CONFLICT --
Package: serde
Constraint: >1.0.5
-- END CONFLICT --

More random logs...
-- BEGIN CONFLICT --
Package: tokio
Constraint: >=1.10.0
-- END CONFLICT --
EOF

cat << 'EOF' > /home/user/registry.json
{
  "serde": ["1.0.4", "1.0.5", "1.0.10", "1.1.0", "2.0.0"],
  "tokio": ["1.9.0", "1.10.0", "1.14.2", "2.0.1"],
  "reqwest": ["0.11.0", "0.11.2"]
}
EOF

chmod -R 777 /home/user
