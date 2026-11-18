#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/audit_processor.cpp
#include <iostream>
#include <sys/stat.h>

int main(int argc, char* argv[]) {
    // Implement permission checking logic here

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
