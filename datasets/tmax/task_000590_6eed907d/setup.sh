#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ git imagemagick fonts-dejavu-core
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    mkdir -p /home/user/prng_project
    cd /home/user/prng_project

    cat << 'EOF' > main.cpp
#include <iostream>
#include <stdint.h>
#include <stdlib.h>

uint64_t prng_step(uint64_t state) {
    return ((state * 6364136223846793005ULL) + 1442695040888963407ULL) ^ (state >> 27);
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    uint64_t state = strtoull(argv[1], NULL, 10);
    int iterations = atoi(argv[2]);
    for(int i = 0; i < iterations; i++) {
        state = prng_step(state);
    }
    std::cout << state << std::endl;
    return 0;
}
EOF

    g++ -O3 main.cpp -o /app/oracle_prng
    strip /app/oracle_prng

    git init
    git config user.name "Original Author"
    git config user.email "author@example.com"
    git add main.cpp
    git commit -m "Initial commit"

    # Harmless refactor
    cat << 'EOF' > main.cpp
#include <iostream>
#include <stdint.h>
#include <stdlib.h>

#define MULTIPLIER 6364136223846793005ULL
#define ADDEND 1442695040888963407ULL

uint64_t prng_step(uint64_t state) {
    return ((state * MULTIPLIER) + ADDEND) ^ (state >> 27);
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    uint64_t state = strtoull(argv[1], NULL, 10);
    int iterations = atoi(argv[2]);
    for(int i = 0; i < iterations; i++) {
        state = prng_step(state);
    }
    std::cout << state << std::endl;
    return 0;
}
EOF
    git add main.cpp
    git commit -m "Extract constants to macros"

    # Introduce bug
    cat << 'EOF' > main.cpp
#include <iostream>
#include <stdint.h>
#include <stdlib.h>

#define MULTIPLIER 6364136223846793001ULL
#define ADDEND 1442695040888963407ULL

uint64_t prng_step(uint64_t state) {
    return ((state * MULTIPLIER) + ADDEND) ^ (state >> 17);
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    uint64_t state = strtoull(argv[1], NULL, 10);
    int iterations = atoi(argv[2]);
    for(int i = 0; i < iterations; i++) {
        state = prng_step(state);
    }
    std::cout << state << std::endl;
    return 0;
}
EOF
    git add main.cpp
    git commit -m "Optimize PRNG constants"

    # Another harmless commit
    cat << 'EOF' > main.cpp
#include <iostream>
#include <stdint.h>
#include <stdlib.h>

// PRNG constants
#define MULTIPLIER 6364136223846793001ULL
#define ADDEND 1442695040888963407ULL

// Step function
uint64_t prng_step(uint64_t state) {
    return ((state * MULTIPLIER) + ADDEND) ^ (state >> 17);
}

int main(int argc, char** argv) {
    if (argc != 3) return 1; // Require seed and iterations
    uint64_t state = strtoull(argv[1], NULL, 10);
    int iterations = atoi(argv[2]);
    for(int i = 0; i < iterations; i++) {
        state = prng_step(state);
    }
    std::cout << state << std::endl;
    return 0;
}
EOF
    git add main.cpp
    git commit -m "Add comments to PRNG"

    convert -size 1200x200 xc:white -pointsize 20 -fill black -annotate +10+100 "Correct PRNG state update: X_{n+1} = ((X_n * 6364136223846793005ULL) + 1442695040888963407ULL) ^ (X_n >> 27)" /app/whiteboard_notes.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
