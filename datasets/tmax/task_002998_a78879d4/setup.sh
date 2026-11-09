#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... good@user.com
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... evil@hacker.com
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... admin@company.com
EOF

    cat << 'EOF' > /home/user/auth_daemon.cpp
#include <iostream>
#include <string>
#include <cstdlib>
#include <sstream>
#include <iomanip>

std::string generate_token(const std::string& username, int timestamp) {
    srand(timestamp);
    int secret = rand();
    std::stringstream ss;
    for (char c : username) {
        ss << std::hex << std::setw(2) << std::setfill('0') << (int)(c ^ (secret % 256));
    }
    return ss.str();
}

int main() {
    std::cout << generate_token("guest", 1698228000) << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
