#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip qemu-utils openssl g++ socat
    pip3 install pytest

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/port_manager.cpp
#include <iostream>

int main() {
    std::string cert_path = "/home/user/certs/cert.pem";
    std::string key_path = "/home/user/certs/key.pem";

    // Output the socat command
    std::cout << "socat openssl-listen:8443,reuseaddr,fork,cert=" << cert_path << ",key=" << key_path << ",verify=0 tcp:127.0.0.1:9090\n"

    return 0
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
