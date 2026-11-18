#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl
    pip3 install pytest

    mkdir -p /home/user/audit_app
    cat << 'EOF' > /home/user/audit_app/logger.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdio>

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    char buffer[512];
    // Vulnerability: Uncontrolled format string (CWE-134)
    snprintf(buffer, sizeof(buffer), argv[1]); 

    std::ofstream logfile("raw_audit.log");
    logfile << buffer << std::endl;
    logfile.close();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
