#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/server_root/uploads
    mkdir -p /home/user/server_root/etc
    mkdir -p /home/user/server_root/hidden

    # Create some files simulating the outcome of uploads
    echo "normal image content" > /home/user/server_root/uploads/image.png
    echo "malicious script" > /home/user/server_root/uploads/shell.php
    echo "sensitive config data" > /home/user/server_root/etc/config.txt
    echo "ssh key data" > /home/user/server_root/hidden/id_rsa

    # Generate logs
    cat << 'EOF' > /home/user/logs/upload.log
2023-10-01T10:00:00Z POST /api/upload?filename=image.png 200
2023-10-01T10:05:00Z POST /api/upload?filename=../etc/config.txt 200
2023-10-01T10:10:00Z POST /api/upload?filename=../../../../../etc/passwd 403
2023-10-01T10:15:00Z POST /api/upload?filename=shell.php 200
2023-10-01T10:20:00Z GET /api/status?filename=none 200
2023-10-01T10:25:00Z POST /api/upload?filename=../hidden/id_rsa 200
2023-10-01T10:30:00Z POST /api/upload?filename=../etc/missing.txt 200
EOF

    # Calculate expected hashes
    HASH_CONFIG=$(sha256sum /home/user/server_root/etc/config.txt | awk '{print $1}')
    HASH_RSA=$(sha256sum /home/user/server_root/hidden/id_rsa | awk '{print $1}')

    # Expected JSON output (for verification)
    cat << EOF > /home/user/expected_audit_report.json
[
  {
    "timestamp": "2023-10-01T10:05:00Z",
    "provided_filename": "../etc/config.txt",
    "resolved_path": "/home/user/server_root/etc/config.txt",
    "sha256": "$HASH_CONFIG",
    "cwe": "CWE-22"
  },
  {
    "timestamp": "2023-10-01T10:25:00Z",
    "provided_filename": "../hidden/id_rsa",
    "resolved_path": "/home/user/server_root/hidden/id_rsa",
    "sha256": "$HASH_RSA",
    "cwe": "CWE-22"
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
