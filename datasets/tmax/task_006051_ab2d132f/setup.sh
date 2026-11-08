#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest build

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_pkg/src/legacy_pkg
    mkdir -p /home/user/artifacts

    # Create the python source
    cat << 'EOF' > /home/user/legacy_pkg/src/legacy_pkg/__init__.py
def hello():
    return "Legacy package restored!"
EOF

    # Create the broken pyproject.toml
    cat << 'EOF' > /home/user/legacy_pkg/pyproject.toml
[build-system]
requires = ["setuptools>=61.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "legacy_pkg"
# INSERT_VERSION_HERE
# INSERT_DEPS_HERE
EOF

    # Create the recipe DSL file
    cat << 'EOF' > /home/user/legacy_pkg/recipe.dsl
PUSH eyJ2ZXJzaW9u
PUSH IjoiMS4yLjMiLCJ
CONCAT
PUSH kZXBzIjpbInJlc
CONCAT
PUSH XVlc3RzIl19
CONCAT
B64DEC
PRINT
EOF

    chown -R user:user /home/user/legacy_pkg
    chown -R user:user /home/user/artifacts

    chmod -R 777 /home/user
