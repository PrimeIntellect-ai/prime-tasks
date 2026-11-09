#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/payloads.txt
7474757474753f2e39752a3b29292d3e
33373b3d3f742a343d
3e3328757474757474753c363b3d742e222e
752a36353b3e29757474757474757474752c3b287536353d7529232936353d
7475747575293b3c3f75747475747475293b3c3f742e222e
EOF

    cat << 'EOF' > /home/user/encoder.c
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    if(argc < 2) {
        printf("Usage: %s <string>\n", argv[0]);
        return 1;
    }
    for(int i=0; i<strlen(argv[1]); i++) {
        printf("%02x", argv[1][i] ^ 0x5A);
    }
    printf("\n");
    return 0;
}
EOF

    gcc /home/user/encoder.c -o /home/user/encoder
    strip /home/user/encoder
    rm /home/user/encoder.c

    chown -R user:user /home/user
    chmod -R 777 /home/user
