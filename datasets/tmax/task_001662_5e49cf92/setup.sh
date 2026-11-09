#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc haproxy curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/prime_c.c
int count_primes(int n) {
    int count = 0;
    for (int i = 2; i <= n; i++) {
        int is_prime = 1;
        for (int j = 2; j * j <= i; j++) {
            if (i % j == 0) {
                is_prime = 0;
                break;
            }
        }
        if (is_prime) count++;
    }
    return count;
}
EOF

    cat << 'EOF' > /home/user/project/prime_py.py
def count_primes(n):
    count = 0
    for i in range(2, n + 1):
        is_prime = True
        j = 2
        while j * j <= i:
            if i % j == 0:
                is_prime = False
                break
            j += 1
        if is_prime:
            count += 1
    return count
EOF

    chmod -R 777 /home/user
