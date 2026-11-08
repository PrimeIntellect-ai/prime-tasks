#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patchelf binutils nasm
    pip3 install pytest

    mkdir -p /home/user/deploy
    cd /home/user/deploy

    # Create liblegacy.c
    cat << 'EOF' > legacy.c
int calculate_magic_constant() {
    return 0;
}
EOF
    gcc -shared -fPIC -o liblegacy.so legacy.c

    # Create libmath_ops.c
    cat << 'EOF' > math_ops.c
extern int calculate_magic_constant();
int do_math() {
    return calculate_magic_constant() * 2;
}
EOF
    gcc -shared -fPIC -o libmath_ops.so math_ops.c -L. -llegacy -Wl,-rpath,'$ORIGIN'

    # Create libcore.c
    cat << 'EOF' > core.c
extern int do_math();
int init_engine() {
    return do_math() + 10;
}
EOF
    gcc -shared -fPIC -o libcore.so core.c -L. -lmath_ops -Wl,-rpath,'$ORIGIN'

    # Create main.c
    cat << 'EOF' > main.c
#include <stdio.h>
extern int init_engine();
int main() {
    printf("Result: %d\n", init_engine());
    return 0;
}
EOF
    gcc -o math_engine main.c -L. -lcore -Wl,-rpath,'$ORIGIN'

    # Cleanup source files
    rm *.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
