#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app
    cat << 'EOF' > /tmp/signer.c
#include <stdlib.h>
int main() {
    int ret = system("sha256sum | awk '{printf \"%s-signed\\n\", $1}'");
    return ret;
}
EOF
    gcc -O2 -s /tmp/signer.c -o /app/metadata_signer
    rm /tmp/signer.c
    chmod +x /app/metadata_signer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
