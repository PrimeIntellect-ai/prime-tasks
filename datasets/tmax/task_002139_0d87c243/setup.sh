#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev binutils gawk rustc cargo
pip3 install pytest

mkdir -p /home/user

# Create the dummy evidence binary
cat << 'EOF' > /home/user/dummy.c
#include <stdio.h>
int main() {
    printf("Evidence binary running.\n");
    return 0;
}
EOF
gcc -O0 -o /home/user/evidence.elf /home/user/dummy.c
rm /home/user/dummy.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
