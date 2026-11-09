#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make
    pip3 install pytest

    mkdir -p /home/user/suspicious_crypto
    cd /home/user/suspicious_crypto

    git config --global user.email "security@example.com"
    git config --global user.name "Security Researcher"
    git init

    cat << 'EOF' > Makefile
crypto_analyzer: main.o crypto_utils.o
	gcc -o crypto_analyzer main.o crypto_utils.o

main.o: main.c
	gcc -c main.c

crypto_utils.o: crypto_utils.c
	gcc -c crypto_utils.c

clean:
	rm -f *.o crypto_analyzer
EOF

    cat << 'EOF' > crypto_utils.h
#ifndef CRYPTO_UTILS_H
#define CRYPTO_UTILS_H

unsigned int analyze_payload(unsigned int seed);

#endif
EOF

    cat << 'EOF' > crypto_utils.c
#include "crypto_utils.h"

unsigned int analyze_payload(unsigned int seed) {
    unsigned int state = seed;
    while (state != 1) {
        if (state % 2 == 0) {
            state = state / 2;
        } else {
            state = 3 * state + 1;
        }
    }
    return state;
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include "crypto_utils.h"

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    unsigned int input = atoi(argv[1]);
    unsigned int result = analyze_payload(input);
    printf("Result: %u\n", result);
    return 0;
}
EOF

    git add Makefile crypto_utils.h crypto_utils.c main.c
    git commit -m "Initial commit: working analyzer"

    # Add some dummy commits
    echo "// dummy 1" >> main.c; git commit -am "Update main 1"
    echo "// dummy 2" >> main.c; git commit -am "Update main 2"
    echo "// dummy 3" >> main.c; git commit -am "Update main 3"

    # Introduce the bad commit (infinite loop for specific payload)
    cat << 'EOF' > crypto_utils.c
#include "crypto_utils.h"

unsigned int analyze_payload(unsigned int seed) {
    unsigned int state = seed;
    while (state != 1) {
        if (state == 370) {
            state = 370; // Malicious infinite loop
        } else if (state % 2 == 0) {
            state = state / 2;
        } else {
            state = 3 * state + 1;
        }
    }
    return state;
}
EOF
    git commit -am "Optimize payload analysis"
    BAD_COMMIT=$(git rev-parse HEAD)
    echo $BAD_COMMIT > /tmp/expected_bad_commit.txt

    # Add more dummy commits
    echo "// dummy 4" >> main.c; git commit -am "Update main 4"
    echo "// dummy 5" >> main.c; git commit -am "Update main 5"

    # Introduce the linker error (multiple definition)
    cat << 'EOF' > crypto_utils.h
#ifndef CRYPTO_UTILS_H
#define CRYPTO_UTILS_H

unsigned int analyze_payload(unsigned int seed);
int global_key = 42; // Causes multiple definition linker error

#endif
EOF
    git commit -am "Add global key configuration"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/suspicious_crypto
    chmod -R 777 /home/user
