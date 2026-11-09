#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts/v1 /home/user/artifacts/v2

    cat << 'EOF' > /home/user/migration.log
[INFO] Initializing migration
[INFO] START migrate art-1
[DEBUG] loading data
[INFO] READ v1
[INFO] WRITE v2
[INFO] SUCCESS art-1
[INFO] START migrate art-2
[INFO] READ v1
[INFO] WRITE v2
[INFO] SUCCESS art-2
[INFO] START migrate art-3
[INFO] READ v1
[ERROR] FAIL art-3
[INFO] START migrate art-4
[INFO] READ v1
[INFO] WRITE v2
[INFO] SUCCESS art-4
[INFO] START migrate art-5
[INFO] READ v1
[INFO] WRITE v2
[INFO] SUCCESS art-5
EOF

    printf '{"id": "art-1", "data": "alpha"}' > /home/user/artifacts/v1/art-1.json
    printf '{"id": "art-2", "data": "beta"}' > /home/user/artifacts/v1/art-2.json
    printf '{"id": "art-3", "data": "gamma"}' > /home/user/artifacts/v1/art-3.json
    printf '{"id": "art-4", "data": "delta"}' > /home/user/artifacts/v1/art-4.json
    printf '{"id": "art-5", "data": "epsilon"}' > /home/user/artifacts/v1/art-5.json

    printf '{"id": "art-1", "version": 2, "checksum": "92898b31a5eb234f9a066b5bafe12048", "data": "alpha"}' > /home/user/artifacts/v2/art-1.json
    printf '{"id": "art-2", "version": 2, "checksum": "wronghash123", "data": "beta"}' > /home/user/artifacts/v2/art-2.json
    printf '{"id": "art-4", "version": 1, "checksum": "093bfcd3d4b6c310c14ec7f016d9da26", "data": "delta"}' > /home/user/artifacts/v2/art-4.json
    printf '{"id": "art-5", "version": 2, "checksum": "32e18b871ed197c36a28cc2c4fb712fc", "data": "epsilon"}' > /home/user/artifacts/v2/art-5.json

    chmod -R 777 /home/user
