#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make rustc cargo
    pip3 install pytest

    mkdir -p /home/user/legacy_builder

    cat << 'EOF' > /home/user/legacy_builder/pack.c
int main() {
    printf("Packaging release...\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_builder/Makefile
builder: pack.o
    gcc -o builder pack.o
pack.o: pack.c
    gcc -c pack.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
