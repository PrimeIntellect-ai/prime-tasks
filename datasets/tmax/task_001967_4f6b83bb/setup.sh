#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget curl jq make build-essential
pip3 install pytest

# Setup yq
mkdir -p /app/yq
wget -qO- https://github.com/kislyuk/yq/archive/refs/tags/v3.2.2.tar.gz | tar -xz -C /app/yq --strip-components=1
sed -i 's/import argparse/import argaprse/g' /app/yq/yq/__init__.py

# Setup corpus
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Clean files
cat << 'EOF' > /app/corpus/clean/config1.yaml
server:
  host: "127.0.0.1"
  port: 8080
EOF

cat << 'EOF' > /app/corpus/clean/config2.json
{
  "database": {
    "user": "admin",
    "host": "localhost"
  }
}
EOF

cat << 'EOF' > /app/corpus/clean/config3.yaml
logging:
  level: "INFO"
  file: "/var/log/app.log"
EOF

cat << 'EOF' > /app/corpus/clean/config4.json
{
  "features": {
    "enable_v2": true,
    "beta_test": false
  }
}
EOF

cat << 'EOF' > /app/corpus/clean/config5.yaml
cache:
  ttl: 3600
  max_items: 1000
EOF

# Evil files
# 2 exact copies of files from clean/ to test hash deduplication
cp /app/corpus/clean/config1.yaml /app/corpus/evil/dup1_config1.yaml
cp /app/corpus/clean/config1.yaml /app/corpus/evil/dup2_config1.yaml

# 1 file containing evil_directive:malware to test regex
cat << 'EOF' > /app/corpus/evil/evil1.yaml
server:
  host: "127.0.0.1"
evil_directive:malware
EOF

# 1 file containing password: secret123 to test regex
cat << 'EOF' > /app/corpus/evil/evil2.yaml
database:
  user: "admin"
  password: secret123
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
