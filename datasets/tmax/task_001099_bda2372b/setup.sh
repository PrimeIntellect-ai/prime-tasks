#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev binutils ltrace strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    mkdir -p /home/user/legacy_repo

    # 1. Setup the Git Repository with the hidden secret
    cd /home/user/legacy_repo
    git init
    git config user.email "dev@company.local"
    git config user.name "Legacy Dev"

    echo "Initializing repository" > README.md
    git add README.md
    git commit -m "Initial commit"

    echo "DB_PASS=h1dd3n_g1t_53cr3t" > db_config.txt
    git add db_config.txt
    git commit -m "Add database configuration"

    git rm db_config.txt
    git commit -m "Remove sensitive data"

    # 2. Create the C binary
    cat << 'EOF' > /home/user/bin/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char* token = getenv("AUTH_TOKEN");
    if (token != NULL && strcmp(token, "v4l1d4t0r_k3y_99") == 0) {
        char* db = getenv("DB_PASS");
        if (db != NULL && strcmp(db, "h1dd3n_g1t_53cr3t") == 0) {
            printf("SYSTEM_OK: FLAG{1nc1d3nt_r3s0lv3d}\n");
            return 0;
        }
    }
    printf("ERROR: Validation failed.\n");
    return 1;
}
EOF

    # Compile the binary
    gcc -O0 /home/user/bin/validator.c -o /home/user/bin/validator
    rm /home/user/bin/validator.c
    chmod +x /home/user/bin/validator

    # Ensure ownership and permissions
    chown -R user:user /home/user/bin /home/user/legacy_repo
    chmod -R 777 /home/user
