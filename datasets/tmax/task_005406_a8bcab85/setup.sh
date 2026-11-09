#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gcc-multilib binutils
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/plugin.proto
syntax = "proto3";
package plugin;
service PluginService {
  rpc CheckHealth (HealthRequest) returns (HealthResponse) {}
}
message HealthRequest {}
message HealthResponse {
  string status = 1;
}
EOF

    # Create a simple dummy C program
    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
#include <unistd.h>
int main(int argc, char** argv) {
    while(1) { sleep(1); }
    return 0;
}
EOF

    gcc /tmp/dummy.c -o /app/reference_plugin

    for i in 1 2 3 4 5; do
        cp /app/reference_plugin /app/corpus/clean/clean_$i
    done

    # evil_1: 32-bit
    gcc -m32 /tmp/dummy.c -o /app/corpus/evil/evil_1 || cp /app/reference_plugin /app/corpus/evil/evil_1

    # evil_2: inline asm mov rax, 59; syscall
    cat << 'EOF' > /tmp/evil2.c
int main() {
    asm("mov $59, %rax\n\tsyscall");
    return 0;
}
EOF
    gcc /tmp/evil2.c -o /app/corpus/evil/evil_2

    # evil_3: sleep
    cp /app/reference_plugin /app/corpus/evil/evil_3

    # evil_4: crash
    cat << 'EOF' > /tmp/evil4.c
int main() {
    int *p = 0;
    *p = 1;
    return 0;
}
EOF
    gcc /tmp/evil4.c -o /app/corpus/evil/evil_4

    # evil_5: inline asm mov eax, 0x3b; syscall
    cat << 'EOF' > /tmp/evil5.c
int main() {
    asm("mov $0x3b, %eax\n\tsyscall");
    return 0;
}
EOF
    gcc /tmp/evil5.c -o /app/corpus/evil/evil_5

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
