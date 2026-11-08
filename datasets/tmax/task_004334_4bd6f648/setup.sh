#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server openssh-client git g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup SSH
    mkdir -p /run/sshd
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cp /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys

    # Disable StrictModes so SSH works despite 777 permissions later
    echo "StrictModes no" >> /etc/ssh/sshd_config

    # Create vendored package
    mkdir -p /app/telemetry-processor-1.0.0
    cat << 'EOF' > /app/telemetry-processor-1.0.0/processor.cpp
#include <iostream>
#include <iomanip>

int main() {
    char c;
    while (std::cin.get(c)) {
        unsigned char processed = static_cast<unsigned char>(c) ^ 0x99;
        std::cout << std::hex << std::uppercase << std::setw(2) << std::setfill('0') 
                  << static_cast<int>(processed) << " ";
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/telemetry-processor-1.0.0/Makefile
telemetry_processor: processor.cpp
	gcc -o telemetry_processor processor.cpp
EOF

    # Create oracle binary
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <iomanip>

int main() {
    char c;
    while (std::cin.get(c)) {
        unsigned char processed = static_cast<unsigned char>(c) ^ 0x55;
        std::cout << std::hex << std::uppercase << std::setw(2) << std::setfill('0') 
                  << static_cast<int>(processed) << " ";
    }
    return 0;
}
EOF
    g++ -o /app/oracle_telemetry_processor /app/oracle.cpp
    rm /app/oracle.cpp
    chmod +x /app/oracle_telemetry_processor

    # Create required directories
    mkdir -p /home/user/build_workspace
    mkdir -p /home/user/deploy

    chmod -R 777 /home/user
