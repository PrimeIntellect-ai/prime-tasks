#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk
    pip3 install pytest

    mkdir -p /home/user/artifacts

    # Create artifact files
    echo "base_system" > /home/user/artifacts/base.tar
    echo "lib_network" > /home/user/artifacts/net.so
    echo "lib_crypto" > /home/user/artifacts/crypto.so
    echo "app_backend" > /home/user/artifacts/backend.bin
    echo "app_frontend" > /home/user/artifacts/frontend.bin
    echo "final_package" > /home/user/artifacts/release.zip

    # Calculate actual checksums
    HASH_BASE=$(sha256sum /home/user/artifacts/base.tar | awk '{print $1}')
    HASH_NET=$(sha256sum /home/user/artifacts/net.so | awk '{print $1}')
    HASH_CRYPTO=$(sha256sum /home/user/artifacts/crypto.so | awk '{print $1}')
    HASH_BACKEND=$(sha256sum /home/user/artifacts/backend.bin | awk '{print $1}')
    HASH_FRONTEND=$(sha256sum /home/user/artifacts/frontend.bin | awk '{print $1}')
    HASH_RELEASE=$(sha256sum /home/user/artifacts/release.zip | awk '{print $1}')

    # Create the ci_deps.graph file
    cat <<EOF > /home/user/ci_deps.graph
release.zip : $HASH_RELEASE : backend.bin,frontend.bin
backend.bin : $HASH_BACKEND : net.so,crypto.so
frontend.bin : $HASH_FRONTEND : net.so
net.so : $HASH_NET : base.tar
crypto.so : $HASH_CRYPTO : base.tar
base.tar : $HASH_BASE : 
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
