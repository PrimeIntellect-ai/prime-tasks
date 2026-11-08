#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mirror

    # Create dummy shared libraries
    echo "content-libcore-1.1.0" > /home/user/mirror/libcore-1.1.0.so
    echo "content-libcore-1.5.0-tampered" > /home/user/mirror/libcore-1.5.0.so
    echo "content-libcore-1.8.5" > /home/user/mirror/libcore-1.8.5.so
    echo "content-libcore-1.10.0" > /home/user/mirror/libcore-1.10.0.so
    echo "content-libcore-2.1.0" > /home/user/mirror/libcore-2.1.0.so

    # Compute real hashes
    HASH_1_1_0=$(sha256sum /home/user/mirror/libcore-1.1.0.so | awk '{print $1}')
    HASH_1_8_5=$(sha256sum /home/user/mirror/libcore-1.8.5.so | awk '{print $1}')
    HASH_1_10_0=$(sha256sum /home/user/mirror/libcore-1.10.0.so | awk '{print $1}')
    HASH_2_1_0=$(sha256sum /home/user/mirror/libcore-2.1.0.so | awk '{print $1}')

    # B64 filenames
    B64_1_1_0=$(echo -n "libcore-1.1.0.so" | base64)
    B64_1_5_0=$(echo -n "libcore-1.5.0.so" | base64)
    B64_1_8_5=$(echo -n "libcore-1.8.5.so" | base64)
    B64_1_10_0=$(echo -n "libcore-1.10.0.so" | base64)
    B64_2_1_0=$(echo -n "libcore-2.1.0.so" | base64)

    # Create index.csv
    cat <<EOF > /home/user/mirror/index.csv
libcore,1.1.0,$B64_1_1_0,$HASH_1_1_0
libcore,1.5.0,$B64_1_5_0,fakehash00000000000000000000000000000000000000000000000000000000
libcore,1.8.5,$B64_1_8_5,$HASH_1_8_5
libcore,1.10.0,$B64_1_10_0,$HASH_1_10_0
libcore,2.1.0,$B64_2_1_0,$HASH_2_1_0
EOF

    chown -R user:user /home/user/mirror
    chmod -R 777 /home/user
