#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_src
    cd /home/user

    # Create files for backup
    head -c 1000 /dev/zero > backup_src/file_a.dat
    head -c 3000 /dev/zero > backup_src/file_b.dat
    head -c 2000 /dev/zero > backup_src/file_c.dat
    head -c 400 /dev/zero > backup_src/file_d.dat

    # Create tarball (strip backup_src directory from paths)
    cd backup_src
    tar -czf /home/user/backup.tar.gz *
    cd /home/user
    rm -rf backup_src

    # Create backup_manifest.json
    cat << 'EOF' > /home/user/backup_manifest.json
[
  {"path": "file_a.dat", "uid": 1001, "size": 1000},
  {"path": "file_b.dat", "uid": 1001, "size": 3000},
  {"path": "file_c.dat", "uid": 1002, "size": 2000},
  {"path": "file_d.dat", "uid": 1003, "size": 500}
]
EOF

    # Create quotas.json
    cat << 'EOF' > /home/user/quotas.json
{
  "1001": {"used": 7000, "limit": 10500},
  "1002": {"used": 9000, "limit": 10000},
  "1003": {"used": 0, "limit": 10000}
}
EOF

    chmod -R 777 /home/user
