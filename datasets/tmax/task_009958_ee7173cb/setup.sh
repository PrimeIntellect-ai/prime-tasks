#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar unzip zip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_docs/api
    mkdir -p /home/user/raw_docs/core
    mkdir -p /home/user/raw_docs/ui

    # Create files for API
    echo "# API v1" > /home/user/raw_docs/api/endpoints.md
    cat << 'EOF' > /home/user/raw_docs/api/endpoints.meta.json
{
    "target_file": "endpoints.md",
    "component": "api",
    "version": "v1.0",
    "status": "approved"
}
EOF

    echo "# Old API" > /home/user/raw_docs/api/legacy.md
    cat << 'EOF' > /home/user/raw_docs/api/legacy.meta.json
{
    "target_file": "legacy.md",
    "component": "api",
    "version": "v0.9",
    "status": "deprecated"
}
EOF

    # Create files for Core
    echo "# Core Engine" > /home/user/raw_docs/core/engine.md
    cat << 'EOF' > /home/user/raw_docs/core/engine.meta.json
{
    "target_file": "engine.md",
    "component": "core",
    "version": "v3.2",
    "status": "approved"
}
EOF

    echo "# Core Draft" > /home/user/raw_docs/core/future.md
    cat << 'EOF' > /home/user/raw_docs/core/future.meta.json
{
    "target_file": "future.md",
    "component": "core",
    "version": "v4.0",
    "status": "draft"
}
EOF

    # Create files for UI
    echo "# UI Components" > /home/user/raw_docs/ui/buttons.md
    cat << 'EOF' > /home/user/raw_docs/ui/buttons.meta.json
{
    "target_file": "buttons.md",
    "component": "frontend",
    "version": "v1.5",
    "status": "approved"
}
EOF

    cd /home/user
    tar -czf raw_docs.tar.gz raw_docs
    rm -rf raw_docs

    # Fetch nlohmann/json for C++ parsing
    wget -qO /home/user/json.hpp https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp

    chmod -R 777 /home/user
