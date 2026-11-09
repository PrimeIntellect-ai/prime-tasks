#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gdb make gcc
    pip3 install pytest

    mkdir -p /home/user/matrix_profiler
    cd /home/user/matrix_profiler

    cat << 'EOF' > main.c
#include <stdio.h>
void compute_matrix();

int main() {
    printf("Starting matrix computation...\n");
    compute_matrix();
    printf("Matrix computation complete\n");
    return 0;
}
EOF

    cat << 'EOF' > matrix.c
#include <stdio.h>

void compute_matrix() {
    int arr[5];
    for(int i = 0; i <= 5; i++) { // BUG: off-by-one causing stack smashing or segfault
        arr[i] = i * 2;
    }
}
EOF

    cat << 'EOF' > Makefile
app_fixed: main.o matrix.o
gcc -o app_fixed main.o matrix.o # BUG: missing tab
main.o: main.c
	gcc -c main.c
matrix.o: matrix.c
	gcc -c matrix.c
EOF

    # Initialize git, add files, and delete matrix.c
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    git add main.c matrix.c Makefile
    git commit -m "Initial commit"
    rm matrix.c
    git add matrix.c
    git commit -m "Remove matrix.c"

    # Compile a buggy version to generate core dump
    cat << 'EOF' > buggy_matrix.c
#include <stdio.h>
void compute_matrix() {
    int *ptr = NULL;
    *ptr = 10; // Forced segfault
}
EOF

    gcc -g -o app_buggy main.c buggy_matrix.c
    rm buggy_matrix.c

    # Generate core dump using GDB to bypass system core_pattern restrictions
    gdb -batch -ex "run" -ex "generate-core-file core" ./app_buggy || true

    # Fallback in case core dump wasn't generated
    if [ ! -f core ]; then
        touch core
    fi

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
