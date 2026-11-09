#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/polybuild/utils
    mkdir -p /home/user/polybuild/core
    mkdir -p /home/user/polybuild/api
    mkdir -p /home/user/polybuild/frontend
    mkdir -p /home/user/polybuild/docs

    cat << 'EOF' > /home/user/polybuild/utils/build.json
{
  "name": "utils",
  "deps": [],
  "cmd": "gcc -o utils utils.c"
}
EOF

    cat << 'EOF' > /home/user/polybuild/core/build.json
{
  "name": "core",
  "deps": ["utils"],
  "cmd": "gcc -o core core.c"
}
EOF

    cat << 'EOF' > /home/user/polybuild/api/build.json
{
  "name": "api",
  "deps": ["core"],
  "cmd": "python build_api.py"
}
EOF

    cat << 'EOF' > /home/user/polybuild/frontend/build.json
{
  "name": "frontend",
  "deps": ["api", "utils"],
  "cmd": "npm run build"
}
EOF

    cat << 'EOF' > /home/user/polybuild/docs/build.json
{
  "name": "docs",
  "deps": [],
  "cmd": "mkdocs build"
}
EOF

    cat << 'EOF' > /home/user/polybuild/cache.json
{
  "utils": "gcc -o utils utils.c",
  "core": "gcc -o core core.c",
  "api": "python build_api_OLD.py",
  "frontend": "npm run build",
  "docs": "mkdocs build"
}
EOF

    chmod -R 777 /home/user
