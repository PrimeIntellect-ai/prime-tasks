#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc binutils zip unzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    # 1. Create the dummy ELF with the custom section
    cat << 'EOF' > /tmp/dummy.c
int main() { return 0; }
EOF
    gcc /tmp/dummy.c -o /home/user/dropper.elf
    # Add the custom .keydata section
    echo -n "KEY_PREFIX=V0rt3x_" > /tmp/keydata.bin
    objcopy --add-section .keydata=/tmp/keydata.bin /home/user/dropper.elf
    rm /tmp/dummy.c /tmp/keydata.bin

    # 2. Create the payload file and its hash
    echo "C2_SERVER=198.51.100.42;PORT=1337;DROP_PATH=/tmp/.cache" > /home/user/payload.bin
    sha256sum /home/user/payload.bin > /home/user/payload.sha256

    # 3. Create the encrypted zip file (Password is V0rt3x_47)
    zip -P V0rt3x_47 /home/user/payload.zip payload.bin
    rm /home/user/payload.bin # Remove original to force extraction

    chmod -R 777 /home/user
