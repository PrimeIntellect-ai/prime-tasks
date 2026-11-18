#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl unzip gcc make
    pip3 install pytest

    mkdir -p /app
    cd /app
    curl -L https://sourceforge.net/projects/libb64/files/libb64/libb64/libb64-1.2.1.zip/download -o libb64.zip
    unzip libb64.zip
    rm libb64.zip

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <b64/cencode.h>

int main() {
    char line[256];
    if (!fgets(line, sizeof(line), stdin)) return 1;

    char *user = strtok(line, ",");
    char *fp = strtok(NULL, ",");
    char *sudo = strtok(NULL, ",\n");

    if (!user || !fp || !sudo) return 1;

    char audit_str[512];
    snprintf(audit_str, sizeof(audit_str), "AUDIT_TOKEN:user=%s:sudo=%s", user, sudo);

    base64_encodestate state;
    base64_init_encodestate(&state);

    char out[1024];
    int c = base64_encode_block(audit_str, strlen(audit_str), out, &state);
    c += base64_encode_blockend(out + c, &state);
    out[c] = '\0';

    printf("%s", out);
    return 0;
}
EOF

    cd /app/libb64-1.2.1
    make
    gcc -I/app/libb64-1.2.1/include /tmp/oracle.c /app/libb64-1.2.1/src/libb64.a -o /app/oracle_audit_token_gen
    make clean
    rm -f /app/libb64-1.2.1/src/libb64.a

    # Perturb the Makefile
    sed -i 's/^\t/    /g' /app/libb64-1.2.1/src/Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
