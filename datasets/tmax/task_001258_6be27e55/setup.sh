#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Create app directory
    mkdir -p /app/semantic_version

    # Download semantic_version 2.10.0
    wget -qO semantic_version.tar.gz https://files.pythonhosted.org/packages/source/s/semantic_version/semantic_version-2.10.0.tar.gz
    tar -xzf semantic_version.tar.gz -C /app/semantic_version --strip-components=1
    rm semantic_version.tar.gz

    # Introduce the bug in base.py
    # Replacing `>= 0` with `< 0` and `<= 0` with `> 0` in the comparison logic
    sed -i 's/>= 0/< 0/g' /app/semantic_version/semantic_version/base.py
    sed -i 's/<= 0/> 0/g' /app/semantic_version/semantic_version/base.py

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create registry.json
    cat << 'EOF' > /home/user/registry.json
{
  "frontend": {
    "1.0.0": {"deps": {}},
    "1.1.0": {"deps": {"backend": ">=2.0.0"}},
    "1.2.0": {"deps": {"backend": ">=2.1.0", "db": ">=1.0.0"}}
  },
  "backend": {
    "2.0.0": {"deps": {}},
    "2.1.0": {"deps": {}},
    "2.2.0": {"deps": {}}
  },
  "db": {
    "1.0.0": {"deps": {}},
    "1.0.1": {"deps": {}}
  }
}
EOF

    chmod -R 777 /home/user
