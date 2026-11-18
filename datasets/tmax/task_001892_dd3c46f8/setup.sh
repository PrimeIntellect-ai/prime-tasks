#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create the legacy_filter binary
    mkdir -p /app
    cat << 'EOF' > /app/legacy_filter.c
#include <stdio.h>
#include <string.h>

int main() {
    char line[2048];
    while (fgets(line, sizeof(line), stdin)) {
        if (!strstr(line, "DEBUG_TRACE")) {
            fputs(line, stdout);
        }
    }
    return 0;
}
EOF
    gcc -O2 /app/legacy_filter.c -o /app/legacy_filter
    strip /app/legacy_filter
    rm /app/legacy_filter.c

    useradd -m -s /bin/bash user || true

    # Create corpora directories and sample files
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/corpora/clean/sample1.log
INFO: User 123-45-6789 logged in. BYTES: 100
DEBUG_TRACE: checking connection. BYTES: 200
INFO: Query executed. BYTES: 300
INFO: User 987-65-4321 logged out. BYTES: 100
EOF

    cat << 'EOF' > /home/user/corpora/evil/sample1.log
INFO: User 123-45-6789 logged in. BYTES: 400
DEBUG_TRACE: checking connection. BYTES: 400
INFO: Query executed. BYTES: 300
INFO: User 987-65-4321 logged out. BYTES: 100
EOF

    chmod -R 777 /home/user
