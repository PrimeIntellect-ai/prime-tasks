#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind build-essential
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > libstatemachine.c
#include <stdio.h>
const char* sm_get_version() { 
    return "1.5.0"; 
}
void sm_process(const char* data) { 
    printf("State machine processed: %s\n", data); 
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern const char* sm_get_version();
extern void sm_process(const char* data);

int main(int argc, char** argv) {
    const char* ver = sm_get_version();
    printf("Library version detected: %s\n", ver);

    // Semantic version comparison check (checking major version)
    if (ver[0] >= '2') {
        printf("Using V2 fast path...\n");
        char* buffer = malloc(256);
        strcpy(buffer, "v2_fast_path_data");
        sm_process(buffer);
        // Memory leak: forgot to free(buffer)
    } else {
        printf("Using V1 slow path...\n");
        sm_process("v1_slow_path_data");
    }
    return 0;
}
EOF

    gcc -shared -fPIC -o libstatemachine.so libstatemachine.c
    gcc -o app main.c -L. -lstatemachine -Wl,-rpath=/home/user/project
    rm main.c libstatemachine.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
