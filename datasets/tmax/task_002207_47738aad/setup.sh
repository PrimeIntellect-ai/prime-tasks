#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/pentest_audit

    cat << 'EOF' > /home/user/pentest_audit/vuln_auth.cpp
#include <iostream>

// Target Admin Hash
const int ADMIN_HASH = 48877;

int custom_hash(int pin) {
    // Weak custom hash function
    return (pin ^ 0x5A5A) * 13 % 99991;
}

bool authenticate(int input_pin) {
    if (custom_hash(input_pin) == ADMIN_HASH) {
        return true;
    }
    return false;
}

int main() {
    int pin;
    std::cout << "Enter PIN: ";
    std::cin >> pin;
    if (authenticate(pin)) {
        std::cout << "Access Granted." << std::endl;
    } else {
        std::cout << "Access Denied." << std::endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pentest_audit/network_logs.txt
[INFO] 192.168.1.50 Attempted login user=guest PIN=1234
[INFO] 10.0.0.5 Attempted login user=admin PIN=0000
[INFO] 10.0.0.5 Attempted login user=admin PIN=1111
[INFO] 10.0.0.5 Attempted login user=admin PIN=2222
[INFO] 10.0.0.5 Attempted login user=admin PIN=3333
[INFO] 192.168.1.100 Attempted login user=admin PIN=4829
[INFO] 172.16.0.4 Attempted login user=guest PIN=9999
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
