#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest packaging

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts
    cd /home/user/artifacts

    echo "binary data 1" > worker_v1.2.3_linux_amd64.bin
    echo "binary data 2" > worker_v1.3.0_linux_arm64.bin
    echo "binary data 3" > worker_v2.0.0-alpha_windows_amd64.bin
    echo "binary data 4" > worker_v1.2.4_darwin_amd64.bin
    echo "binary data 5" > worker_v2.0.1_linux_amd64.bin
    echo "binary data 6" > worker_v2.1.0-rc.1_darwin_arm64.bin

    sha256sum worker_v1.2.3_linux_amd64.bin > checksums.txt
    sha256sum worker_v2.0.0-alpha_windows_amd64.bin >> checksums.txt
    sha256sum worker_v2.0.1_linux_amd64.bin >> checksums.txt
    sha256sum worker_v2.1.0-rc.1_darwin_arm64.bin >> checksums.txt

    echo "1111111111111111111111111111111111111111111111111111111111111111  worker_v1.3.0_linux_arm64.bin" >> checksums.txt
    echo "2222222222222222222222222222222222222222222222222222222222222222  worker_v1.2.4_darwin_amd64.bin" >> checksums.txt

    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
