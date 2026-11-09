#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils socat netcat-openbsd gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /app

    cat << 'EOF' > /app/compiler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[4096];
    // Magic header "TMPK"
    fwrite("TMPK", 1, 4, stdout);
    // Simple XOR cipher instead of zlib to keep binary self-contained and stripped easily
    while (fgets(buffer, sizeof(buffer), stdin)) {
        for(int i = 0; buffer[i] != '\0'; i++) {
            buffer[i] ^= 0x42;
        }
        fwrite(buffer, 1, strlen(buffer), stdout);
    }
    return 0;
}
EOF
    gcc -O2 /app/compiler.c -o /app/tm_compiler
    strip /app/tm_compiler
    rm /app/compiler.c
    chmod +x /app/tm_compiler

    cat << 'EOF' > /home/user/l10n_logs.csv
2023-10-04T14:32:01Z | 192.168.1.5 | alice@vendor.com | UPDATE | Hello World | Bonjour le monde
2023-10-04T14:33:00Z | 10.0.0.1 | bob@vendor.com | MISSING | Settings | 
2023-10-04T15:01:00Z | 10.0.0.1 | bob@vendor.com | UPDATE | Hello World | Salut tout le monde
2023-10-04T15:05:00Z | 172.16.0.2 | charlie@vendor.com | UPDATE | Save | Enregistrer
EOF

    for i in {10..21}; do
        echo "2023-10-04T16:$i:00Z | 8.8.8.8 | bot@vendor.com | MISSING | Error $i | " >> /home/user/l10n_logs.csv
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
