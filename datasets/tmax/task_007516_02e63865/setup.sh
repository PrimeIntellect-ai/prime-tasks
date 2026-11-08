#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential jq tar gzip gawk rustc cargo
    pip3 install pytest

    mkdir -p /home/user/artifacts/linux/amd64
    mkdir -p /home/user/artifacts/linux/arm64
    mkdir -p /home/user/artifacts/windows/amd64
    mkdir -p /home/user/quarantine

    # Create valid tarballs
    mkdir -p /tmp/dummy_content
    echo "valid artifact data 1" > /tmp/dummy_content/data1.txt
    tar -czf /home/user/artifacts/linux/amd64/app_v1.tar.gz -C /tmp/dummy_content data1.txt
    echo "valid artifact data 2" > /tmp/dummy_content/data2.txt
    tar -czf /home/user/artifacts/linux/arm64/app_v1.tar.gz -C /tmp/dummy_content data2.txt
    echo "valid artifact data 3" > /tmp/dummy_content/data3.txt
    tar -czf /home/user/artifacts/windows/amd64/app_v2.tar.gz -C /tmp/dummy_content data3.txt

    # Create corrupted tarballs
    head -c 100 /dev/urandom > /home/user/artifacts/linux/amd64/corrupt_app.tar.gz
    head -c 50 /dev/urandom > /home/user/artifacts/windows/amd64/broken_v1.tar.gz

    # Pre-calculate hashes of valid tarballs for verification
    HASH1=$(sha256sum /home/user/artifacts/linux/amd64/app_v1.tar.gz | awk '{print $1}')
    HASH2=$(sha256sum /home/user/artifacts/linux/arm64/app_v1.tar.gz | awk '{print $1}')
    HASH3=$(sha256sum /home/user/artifacts/windows/amd64/app_v2.tar.gz | awk '{print $1}')

    # Write expected manifest for the verification script
    cat <<EOF > /home/user/.expected_manifest.json
{
  "files": [
    {
      "path": "linux/amd64/app_v1.tar.gz",
      "checksum": "${HASH1}"
    },
    {
      "path": "linux/arm64/app_v1.tar.gz",
      "checksum": "${HASH2}"
    },
    {
      "path": "windows/amd64/app_v2.tar.gz",
      "checksum": "${HASH3}"
    }
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
