#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/packages/logger
cat << 'EOF' > /home/user/packages/logger/pkg_info.json
{
  "name": "logger",
  "version": "1.5.0",
  "dependencies": {}
}
EOF

mkdir -p /home/user/packages/config
cat << 'EOF' > /home/user/packages/config/pkg_info.json
{
  "name": "config",
  "version": "2.0.0",
  "dependencies": {}
}
EOF

mkdir -p /home/user/packages/database
cat << 'EOF' > /home/user/packages/database/pkg_info.json
{
  "name": "database",
  "version": "1.1.0",
  "dependencies": {
    "logger": ">= 1.0.0",
    "config": "== 2.0.0"
  }
}
EOF

mkdir -p /home/user/packages/auth
cat << 'EOF' > /home/user/packages/auth/pkg_info.json
{
  "name": "auth",
  "version": "1.0.0",
  "dependencies": {
    "database": ">= 1.0.0",
    "logger": ">= 1.2.0"
  }
}
EOF

mkdir -p /home/user/packages/cache
cat << 'EOF' > /home/user/packages/cache/pkg_info.json
{
  "name": "cache",
  "version": "0.9.0",
  "dependencies": {
    "logger": ">= 1.5.0"
  }
}
EOF

mkdir -p /home/user/packages/api
cat << 'EOF' > /home/user/packages/api/pkg_info.json
{
  "name": "api",
  "version": "3.0.0",
  "dependencies": {
    "auth": ">= 1.0.0",
    "cache": ">= 0.9.0",
    "database": ">= 1.0.0"
  }
}
EOF

mkdir -p /home/user/packages/broken_plugin
cat << 'EOF' > /home/user/packages/broken_plugin/pkg_info.json
{
  "name": "broken_plugin",
  "version": "1.0.0",
  "dependencies": {
    "logger": "< 1.0.0"
  }
}
EOF

mkdir -p /home/user/packages/dependent_broken
cat << 'EOF' > /home/user/packages/dependent_broken/pkg_info.json
{
  "name": "dependent_broken",
  "version": "1.0.0",
  "dependencies": {
    "broken_plugin": ">= 1.0.0"
  }
}
EOF

chown -R user:user /home/user/packages
chmod -R 777 /home/user
