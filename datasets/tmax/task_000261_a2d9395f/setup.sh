#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/Makefile
all: libcustom.so app

libcustom.so: libcustom.c
	gcc -shared -fPIC -o libcustom.so libcustom.c

app: main.c libcustom.so
	gcc -o app main.c -L. -lcustom

clean:
	rm -f app libcustom.so
EOF

    cat << 'EOF' > /home/user/project/libcustom.c
#include <stdlib.h>

void process_data() {
    // Intentional memory leak of 128 bytes
    void *ptr = malloc(128);
    (void)ptr; 
}
EOF

    cat << 'EOF' > /home/user/project/main.c
extern void process_data();

int main() {
    process_data();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
