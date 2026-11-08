#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create directories
    mkdir -p /home/user/artifacts/loop
    mkdir -p /home/user/artifacts/standard

    # 2. Create actual binary artifacts
    echo "alpha_data_v1" > /home/user/artifacts/loop/alpha.bin
    echo "beta_data_v1" > /home/user/artifacts/standard/beta.bin
    echo "gamma_data_v1" > /home/user/artifacts/standard/gamma.bin

    # 3. Create a symlink loop
    ln -s /home/user/artifacts/loop /home/user/artifacts/loop/link

    # 4. Generate the corrupt manifest
    cat << 'EOF' > /home/user/corrupt_manifest.log
[Artifact]
ID: 10
Path: /home/user/artifacts/loop/link/alpha.bin
Status: verified
---
[Artifact]
ID: 45
Path: /home/user/artifacts/loop/link/link/link/alpha.bin
Status: verified
---
[Artifact]
ID: 8
Path: /home/user/artifacts/standard/beta.bin
Status: verified
---
[Artifact]
ID: 99
Path: /home/user/artifacts/standard/beta.bin
Status: unverified
---
[Artifact]
ID: 102
Path: /home/user/artifacts/standard/gamma.bin
Status: verified
---
[Artifact]
ID: 105
Path: /home/user/artifacts/standard/doesnotexist.bin
Status: verified
---
EOF

    chmod -R 777 /home/user
