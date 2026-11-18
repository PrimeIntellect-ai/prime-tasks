#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # 1. Create the legacy_hash.cpp file
    cat << 'EOF' > /home/user/legacy_hash.cpp
#include <iostream>
#include <string>
#include <stdint.h>

// Legacy hash function used for authentication
uint32_t legacy_hash(const std::string& str) {
    uint32_t hash = 5381;
    for (char c : str) {
        hash = ((hash << 5) + hash) + c; // hash * 33 + c
    }
    return hash;
}

int main(int argc, char** argv) {
    if (argc > 1) {
        std::cout << legacy_hash(argv[1]) << std::endl;
    }
    return 0;
}
EOF

    # 2. Create the old_hash.txt file
    echo -n "263435403" > /home/user/old_hash.txt

    # 3. Create and encrypt the new config
    echo "NEW_CREDENTIAL=super_secret_p4ssw0rd_99" > /tmp/new_config.txt
    openssl enc -aes-256-cbc -pbkdf2 -in /tmp/new_config.txt -out /home/user/new_config.enc -pass pass:nukes
    rm /tmp/new_config.txt

    # 4. Create the log file
    cat << 'EOF' > /home/user/auth_access.log
[2023-10-01T10:00:00Z] 192.168.1.50 LOGIN admin password123 STATUS:REJECTED
[2023-10-01T10:05:00Z] 10.0.0.5 LOGIN admin nukes STATUS:REJECTED
[2023-10-01T10:10:00Z] 172.16.0.4 LOGIN admin nukes STATUS:REJECTED
[2023-10-01T10:15:00Z] 192.168.1.100 LOGIN admin correct_old STATUS:ACCEPTED
[2023-10-01T10:18:00Z] 10.0.0.5 LOGIN admin nukes STATUS:REJECTED
[2023-10-01T10:20:00Z] 8.8.8.8 LOGIN root nukes STATUS:ACCEPTED
[2023-10-01T10:25:00Z] 203.0.113.42 LOGIN admin nukes STATUS:REJECTED
EOF

    chmod -R 777 /home/user
