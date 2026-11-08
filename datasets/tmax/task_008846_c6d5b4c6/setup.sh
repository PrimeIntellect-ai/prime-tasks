#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y openssl libssl-dev bubblewrap g++

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    cd /home/user

    # Create CA and Certificate
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/CN=TrustedCA"
    openssl req -newkey rsa:2048 -keyout cert.key -out cert.csr -nodes -subj "/CN=CompromisedClient"
    openssl x509 -req -in cert.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out cert.pem -days 365

    # Create the dropper payload
    cat << 'EOF' > /home/user/dropper.cpp
#include <iostream>
int main() {
    std::cout << "EXPLOIT_PAYLOAD_EXECUTION_SUCCESSFUL_C2_CONNECTING..." << std::endl;
    return 0;
}
EOF
    g++ -o /home/user/dropper /home/user/dropper.cpp
    chmod +x /home/user/dropper

    # Clean up source files
    rm /home/user/dropper.cpp /home/user/ca.key /home/user/cert.key /home/user/cert.csr /home/user/ca.srl || true

    # Set permissions
    chmod -R 777 /home/user
