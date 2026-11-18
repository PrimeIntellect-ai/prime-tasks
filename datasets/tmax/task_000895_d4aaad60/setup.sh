#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs/module_a
    mkdir -p /home/user/docs/module_b
    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/doc_config.ini
[Terms]
master = primary
slave = replica
blacklist = denylist
whitelist = allowlist

[Backup]
target_dir = /home/user/backups
EOF

    cat << 'EOF' > /home/user/docs/module_a/architecture.md
The master node controls the cluster.
If the master fails, a slave takes over.
EOF

    cat << 'EOF' > /home/user/docs/module_a/networking.md
Standard networking setup.
Nothing to change here.
EOF

    cat << 'EOF' > /home/user/docs/module_b/security.md
Ensure IP is not on the blacklist.
Add trusted IPs to the whitelist.
EOF

    cat << 'EOF' > /home/user/docs/new_guide.md
This is a new guide created after the snapshot.
It has no bad terms but should be backed up.
EOF

    cat << 'EOF' > /home/user/backups/snapshot.json
{
  "module_a/architecture.md": "025dc98a72c114cb9126d40df5f7de2e",
  "module_a/networking.md": "208761ed81e3a4e9b9c9f65809bb68d6",
  "module_b/security.md": "a59e19e7a8e52e463bd9b2e7c4856037"
}
EOF

    chmod -R 777 /home/user
