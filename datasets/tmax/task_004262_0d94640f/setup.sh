#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git binutils gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdint.h>

int main() {
    double hash = 0.0;
    const char* magic = "F0r3ns1cs_M4g1c_8923";
    int magic_len = 20;
    int i = 0;
    int c;
    while ((c = getchar()) != EOF) {
        hash = (hash * 31.0000001) + (c ^ magic[i % magic_len]);
        i++;
    }
    printf("%08x\n", (uint32_t)hash);
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/legacy_calc
    strip /app/legacy_calc
    rm /app/oracle.c

    mkdir -p /home/user/hash_repo
    cd /home/user/hash_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdint.h>

int main() {
    double hash = 0.0;
    const char* magic = "PLACEHOLDER_STRING";
    int magic_len = 18;
    int i = 0;
    int c;
    while ((c = getchar()) != EOF) {
        hash = (hash * 31.0000001) + (c ^ magic[i % magic_len]);
        i++;
    }
    printf("%08x\n", (uint32_t)hash);
    return 0;
}
EOF
    git add main.c
    git commit -m "Initial commit with placeholder magic string"

    echo "// dummy 1" >> main.c
    git commit -am "Dummy commit 1"

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdint.h>

int main() {
    float hash = 0.0f;
    const char* magic = "PLACEHOLDER_STRING";
    int magic_len = 18;
    int i = 0;
    int c;
    while ((c = getchar()) != EOF) {
        hash = (hash * 31.0f) + (c ^ magic[i % magic_len]);
        i++;
    }
    printf("%08x\n", (uint32_t)hash);
    return 0;
}
EOF
    git commit -am "Refactor hash to use float for performance"

    echo "// dummy 2" >> main.c
    git commit -am "Dummy commit 2"

    echo "// dummy 3" >> main.c
    git commit -am "Dummy commit 3"

    chmod -R 777 /home/user
