#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpora/clean/subdir
    mkdir -p /app/corpora/evil/subdir

    cat << 'EOF' > /app/corpora/clean/subdir/clean1.log
Host: alpha
SetPrivilege: false
Timeout: 5000
---END RECORD---
Host: beta
SetPrivilege: true
Timeout: 1000
---END RECORD---
EOF

    cat << 'EOF' > /app/corpora/evil/subdir/evil1.log
Host: gamma
SetPrivilege: true
Timeout: 10000
---END RECORD---
Host: delta
SetPrivilege: false
Timeout: 20000
---END RECORD---
EOF

    cat << 'EOF' > /tmp/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[1024];
    int priv = 0;
    while (fgets(buffer, sizeof(buffer), stdin)) {
        if (strstr(buffer, "SetPrivilege: true")) {
            priv = 1;
        } else if (priv && strstr(buffer, "Timeout: ")) {
            int timeout = atoi(buffer + 9);
            if (timeout > 9999) {
                printf("BACKDOOR_TRIGGERED\n");
                return 42;
            }
            priv = 0;
        } else if (strstr(buffer, "---END RECORD---")) {
            priv = 0;
        }
    }
    return 0;
}
EOF
    gcc -o /app/legacy_parser /tmp/parser.c
    strip /app/legacy_parser
    rm /tmp/parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
