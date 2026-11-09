#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/uploads

    echo "Dummy PDF content" > /home/user/uploads/invoice.pdf
    echo "Dummy JPG content" > /home/user/uploads/profile.jpg
    echo "System log started" > /home/user/uploads/system.log

    cat << 'EOF' > /tmp/malware.c
#include <stdio.h>
const char* auth = "AUTH_TOKEN=sk_live_f893jc84nf820fn28hf29023nf923";
int main() {
    printf("Nothing to see here.\n");
    return 0;
}
EOF

    gcc /tmp/malware.c -o /home/user/uploads/avatar_774.png
    rm /tmp/malware.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
