#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip valgrind sqlite3 gcc make binutils wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/verifier

    cat << 'EOF' > /home/user/verifier/main.c
#include <stdio.h>

extern double compute_hash(double val);

int get_deployment_pin() {
    return 1337; // 0x539
}

int main(int argc, char** argv) {
    double res = compute_hash(42.0);
    printf("Result: %f\n", res);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/verifier/crypto_utils.c
#include <math.h>

double compute_hash(double val) {
    return sqrt(val) * 2.5;
}
EOF

    cat << 'EOF' > /home/user/verifier/Makefile
all: verifier

verifier: main.o crypto_utils.o
	gcc -o verifier -lm main.o crypto_utils.o

main.o: main.c
	gcc -c main.c

crypto_utils.o: crypto_utils.c
	gcc -c crypto_utils.c

clean:
	rm -f *.o verifier
EOF

    sqlite3 /home/user/deploy.db "CREATE TABLE releases (id INTEGER PRIMARY KEY, version TEXT);"
    sqlite3 /home/user/deploy.db "INSERT INTO releases (version) VALUES ('v1.0.0');"

    wget -qO /usr/local/bin/websocat https://github.com/vi/websocat/releases/download/v1.11.0/websocat.x86_64-unknown-linux-musl
    chmod +x /usr/local/bin/websocat

    chmod -R 777 /home/user
