#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/net_monitor.cpp
// /home/user/net_monitor.cpp
#include <string>

int main() {
    const char* hosts = getenv("TARGET_HOSTS");
    if (!hosts) {
        std::cerr << "TARGET_HOSTS not set" << std::endl;
        return 1;
    }
    // Syntax error below (missing semicolon)
    std::string h(hosts)
    std::cout << "Monitoring hosts: " << h << std::endl;
    return 0;
}
EOF

    mkdir -p /home/user/logs
    touch /home/user/.bashrc

    chmod -R 777 /home/user
