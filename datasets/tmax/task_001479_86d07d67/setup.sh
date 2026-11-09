#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install additional dependencies for C++ compilation, OpenSSL, and wget
    apt-get install -y g++ libssl-dev wget

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /home/user/extracted

    # Create config.json
    cat << 'EOF' > /home/user/config.json
{
  "allowed_base_dir": "/home/user/extracted",
  "max_total_bytes": 100
}
EOF

    # Create manifest.json
    cat << 'EOF' > /home/user/manifest.json
[
  {
    "path": "safe_doc1.txt",
    "content": "Hello World!"
  },
  {
    "path": "../../../home/user/hacked.txt",
    "content": "Malicious payload!"
  },
  {
    "path": "subfolder/safe_doc2.txt",
    "content": "Safe content."
  },
  {
    "path": "/etc/shadow",
    "content": "root:x:..."
  },
  {
    "path": "safe_doc3.txt",
    "content": "This file is going to exceed the 100 byte quota limit if we aren't careful, so it should be skipped."
  }
]
EOF

    # Set permissions
    chmod -R 777 /home/user
