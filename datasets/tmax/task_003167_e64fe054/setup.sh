#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make coreutils
    pip3 install pytest

    mkdir -p /app/libprime-1.0.0
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/libprime-1.0.0/prime.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int is_prime(int n) {
    if (n <= 1) return 0;
    if (n == 2) return 1;
    if (n % 2 == 0) return 0;
    int limit = (int)sqrt(n);
    for (int i = 3; i <= limit; i += 2) {
        if (n % i == 0) return 0;
    }
    return 1;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    int count = 0;
    int current = 1;
    while (count < n) {
        current++;
        if (is_prime(current)) {
            count++;
        }
    }
    printf("%d", current);
    return 0;
}
EOF

    cat << 'EOF' > /app/libprime-1.0.0/Makefile
all: prime

prime: prime.c
    gcc -O2 prime.c -o prime
EOF

    cat << 'EOF' > /app/prime_encoder.sh
#!/bin/bash
N=$1
# Bug 1: off-by-one (N+1 instead of N)
PRIME=$(/app/libprime-1.0.0/prime $((N + 1)))
# Bug 2: echo adds a newline before base64, and base64 doesn't have -w 0
echo "PRIME:$PRIME" | base64
EOF
    chmod +x /app/prime_encoder.sh

    cat << 'EOF' > /opt/oracle/prime_encoder.sh
#!/bin/bash
N=$1
PRIME=$(/app/libprime-1.0.0/prime $N)
printf "PRIME:%s" "$PRIME" | base64 -w 0
EOF
    chmod +x /opt/oracle/prime_encoder.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
