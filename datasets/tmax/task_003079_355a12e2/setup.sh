#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/incoming
    mkdir -p /home/user/tmp_setup

    # Create repo_config.json
    cat << 'EOF' > /home/user/repo_config.json
{
  "allowed_architectures": ["x86_64", "arm64"],
  "allowed_extensions": [".tar.gz"],
  "output_dir": "/home/user/repo",
  "manifest_path": "/home/user/repo/manifest.json"
}
EOF

    # Create dummy nested files
    mkdir -p /home/user/tmp_setup/b1
    mkdir -p /home/user/tmp_setup/b2

    # Batch 1
    echo "dummy x86_64 binary tool A" > /home/user/tmp_setup/b1/binary_a
    tar -czf /home/user/tmp_setup/b1/toolA-1.0-x86_64.tar.gz -C /home/user/tmp_setup/b1 binary_a
    echo "dummy i386 binary tool A" > /home/user/tmp_setup/b1/binary_a_i386
    tar -czf /home/user/tmp_setup/b1/toolA-1.0-i386.tar.gz -C /home/user/tmp_setup/b1 binary_a_i386
    echo "readme info" > /home/user/tmp_setup/b1/readme.txt

    # Batch 2
    echo "dummy arm64 binary tool B" > /home/user/tmp_setup/b2/binary_b
    tar -czf /home/user/tmp_setup/b2/toolB-2.0-arm64.tar.gz -C /home/user/tmp_setup/b2 binary_b
    echo "dummy arm64 wrong ext" > /home/user/tmp_setup/b2/toolB-2.0-arm64.zip

    # Zip them up into the incoming directory
    cd /home/user/tmp_setup/b1 && zip -r /home/user/incoming/batch1.zip .
    cd /home/user/tmp_setup/b2 && zip -r /home/user/incoming/batch2.zip .

    # Cleanup
    rm -rf /home/user/tmp_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
