#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    mkdir -p /home/user/math_build/deps/v1
    mkdir -p /home/user/math_build/deps/v2

    # Create the correct header
    cat << 'EOF' > /home/user/math_build/deps/v1/constants.h
#ifndef CONSTANTS_H
#define CONSTANTS_H
#define PI_VALUE 3.14159
#endif
EOF

    # Create the conflicting header
    cat << 'EOF' > /home/user/math_build/deps/v2/constants.h
#ifndef CONSTANTS_H
#define CONSTANTS_H
#error "FATAL: This version of constants.h is deprecated and contains conflicting types!"
#endif
EOF

    # Create the C program
    cat << 'EOF' > /home/user/math_build/matrix_magic.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "constants.h"

int main() {
    char* key = getenv("MATH_API_KEY");
    if (!key) {
        printf("Error: MATH_API_KEY environment variable not set\n");
        return 1;
    }

    // Use the API key as a hex seed
    long seed = strtol(key, NULL, 16);
    if (seed <= 0) {
        printf("Error: Invalid MATH_API_KEY\n");
        return 1;
    }

    double result = sqrt(seed) * PI_VALUE;
    printf("%.2f\n", result);
    return 0;
}
EOF

    # Setup Git Repo
    cd /home/user/math_build
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1: Initial commit, working build script but no key logic
    cat << 'EOF' > build.sh
#!/bin/bash
gcc matrix_magic.c -I./deps/v1 -lm -o matrix_magic
EOF
    chmod +x build.sh
    git add .
    git commit -m "Initial commit: basic math program"

    # Commit 2: Added hardcoded secret
    cat << 'EOF' > build.sh
#!/bin/bash
export MATH_API_KEY="1a2b3c"
gcc matrix_magic.c -I./deps/v1 -lm -o matrix_magic
./matrix_magic
EOF
    git add build.sh
    git commit -m "Testing API key for math seed"

    # Commit 3: Removed secret for security, but broke the build script
    cat << 'EOF' > build.sh
#!/bin/bash
# Removed secret key
gcc matrix_magic.c -I./deps/v2 -I./deps/v1 -o matrix_magic
EOF
    git add build.sh
    git commit -m "Remove hardcoded MATH_API_KEY and update includes"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/math_build
    chmod -R 777 /home/user
