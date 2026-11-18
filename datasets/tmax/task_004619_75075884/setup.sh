#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required dependencies
    apt-get install -y curl build-essential imagemagick tesseract-ocr fonts-dejavu-core

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil /app

    # Generate the legacy schema image using -annotate to avoid quote escaping issues
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -annotate +10+50 "CRITICAL: When target_version is v2, the" \
        -annotate +10+90 "pre_deploy_hook MUST NOT contain the substring 'exec'." \
        /app/legacy_schema.png

    # Generate Clean Corpus
    cat << 'EOF' > /app/corpus/clean/valid1.json
{
  "previous_version": "v1",
  "target_version": "v2",
  "pre_deploy_hook": "echo 'starting'",
  "services": [ { "name": "web", "image": "nginx:latest" } ]
}
EOF

    cat << 'EOF' > /app/corpus/clean/valid2.json
{
  "previous_version": "v2",
  "target_version": "v2",
  "pre_deploy_hook": "exec custom_script.sh",
  "services": [ { "name": "db", "image": "postgres:14" } ]
}
EOF

    # Generate Evil Corpus
    cat << 'EOF' > /app/corpus/evil/invalid_empty_services.json
{
  "previous_version": "v1",
  "target_version": "v2",
  "pre_deploy_hook": "echo 'starting'",
  "services": []
}
EOF

    cat << 'EOF' > /app/corpus/evil/invalid_rule_violation.json
{
  "previous_version": "v1",
  "target_version": "v2",
  "pre_deploy_hook": "chmod +x script.sh && exec ./script.sh",
  "services": [ { "name": "web", "image": "nginx:latest" } ]
}
EOF

    cat << 'EOF' > /app/corpus/evil/invalid_rule_violation2.json
{
  "previous_version": "v1",
  "target_version": "v2",
  "pre_deploy_hook": "exec bash -i",
  "services": [ { "name": "backend", "image": "node:18" } ]
}
EOF

    # Set permissions
    chmod -R 777 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
