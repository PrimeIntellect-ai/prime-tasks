#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/backup_topology.txt
db-main backup-tier1
db-analytics backup-tier1
db-users backup-tier2
db-edge1 backup-tier2
db-edge2 backup-edge
backup-tier1 vault-primary
backup-tier2 vault-primary
db-legacy vault-primary
vault-primary vault-dr
vault-dr vault-primary
backup-edge vault-dr
isolated-db isolated-vault
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
