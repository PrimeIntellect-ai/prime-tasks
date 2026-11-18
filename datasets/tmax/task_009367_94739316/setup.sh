#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc time
    pip3 install pytest

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/worker.c
#include <stdlib.h>
#include <unistd.h>

int main() {
    for(int i=0; i<50; i++) {
        void *p = malloc(1024 * 1024); // 1MB allocation
        // Simulate some work
        for(int j=0; j<1000; j++) { ((char*)p)[j] = 'a'; }
#ifdef ARCH_X86
        free(p);
#endif
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
