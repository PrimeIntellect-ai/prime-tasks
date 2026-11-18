#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tar gzip
    pip3 install pytest

    mkdir -p /home/user/artifacts/extracted_temp
    cd /home/user/artifacts/extracted_temp

    # Create dummy binaries
    echo -n "linux-amd64-v1.0.0" > bin_1.dat
    echo -n "darwin-arm64-v1.0.0" > bin_2.dat
    echo -n "windows-amd64-v1.0.0" > bin_3.dat

    # Create metadata.json
    cat << 'EOF' > metadata.json
[
  {
    "id": "bin_1.dat",
    "target_name": "release_v1.0.0-linux-amd64.bin",
    "expected_sha256": "c9158fb7ff6645db7d264f3c75ebbd7806f1d9bd5c2f82684821a71af2747120"
  },
  {
    "id": "bin_2.dat",
    "target_name": "release_v1.0.0-darwin-arm64.bin",
    "expected_sha256": "00b0f20d6fcc4cd15494d4a51eec77e23117dd1081a29ffbf7c5035f586a117b"
  },
  {
    "id": "bin_3.dat",
    "target_name": "release_v1.0.0-windows-amd64.exe",
    "expected_sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  }
]
EOF

    tar -czf /home/user/artifacts/raw_binaries.tar.gz *
    cd /home/user
    rm -rf /home/user/artifacts/extracted_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
