#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/math_util
    cd /home/user/math_util

    cat << 'EOF' > ref.py
def compute():
    m = 1000000007
    seed = 12345
    total = 0
    for i in range(1, 100001):
        seed = (seed * i) % m
        total = (total + seed) % m
    return total

if __name__ == "__main__":
    print(compute())
EOF

    cat << 'EOF' > fast_math.s
.global fast_mult
.text
fast_mult:
    # System V AMD64 ABI: rdi = a, rsi = b, rdx = m
    mov %rdx, %rcx   # Save m into rcx because rdx is used by mul/div
    mov %rdi, %rax   # rax = a
    mul %rsi         # rdx:rax = a * b
    div %rcx         # Divide rdx:rax by rcx (m). rax = quotient, rdx = remainder
    mov %rdx, %rax   # Return the remainder in rax
    ret
EOF

    cat << 'EOF' > fast_math.h
#include <stdint.h>
uint64_t fast_mult(uint64_t a, uint64_t b, uint64_t m);
EOF

    python3 ref.py > /home/user/math_util/.expected

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/math_util
    chmod -R 777 /home/user
