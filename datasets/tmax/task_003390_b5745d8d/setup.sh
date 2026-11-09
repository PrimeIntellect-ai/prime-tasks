#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/query-builder-1.0.0/query_builder
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create vendored package files
    cat << 'EOF' > /app/vendored/query-builder-1.0.0/pyproject.toml
[build-system]
requires = ["setuptools", "fake-build-backend"]
build-backend = "setuptools.build_meta"

[project]
name = "query-builder"
version = "1.0.0"
EOF

    cat << 'EOF' > /app/vendored/query-builder-1.0.0/query_builder/__init__.py
def build_query(dsl):
    return "SELECT * FROM " + dsl.get("table", "unknown")
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/1.json
{"table": "users", "columns": ["id", "name"]}
EOF

    cat << 'EOF' > /app/corpora/clean/2.json
{"table": "transactions", "columns": ["id", "amount", "date"], "window": "ROW_NUMBER() OVER (PARTITION BY date)"}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/1.json
{"table": "users; DROP TABLE users; --", "columns": ["id"]}
EOF

    cat << 'EOF' > /app/corpora/evil/2.json
{"table": "transactions", "columns": ["id", "amount UNION SELECT password FROM admin"]}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
