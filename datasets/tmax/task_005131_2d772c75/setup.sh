#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/wordlist.txt
password123
admin
qwerty
letmein
hunter2
winter2023
supersecret
EOF

    cat << 'EOF' > /home/user/custom_hash.h
#ifndef CUSTOM_HASH_H
#define CUSTOM_HASH_H
#include <string>

inline unsigned int compute_hash(const std::string& password) {
    unsigned int hash = 0;
    for (size_t i = 0; i < password.length(); ++i) {
        hash = (hash * 31) + password[i];
    }
    return hash ^ 0xDEADBEEF;
}
#endif
EOF

    cat << 'EOF' > /home/user/auth_logs.txt
[2023-10-24 10:00:01] user=sysadmin redirect_payload=aHR0cDovL2V2aWwuY29tL3N0ZWFs hash=DF5165E0
[2023-10-24 10:05:22] user=devteam redirect_payload=aHR0cHM6Ly9waGlzaC5uZXQvbG9naW4= hash=DE5689EF
EOF

    touch /home/user/ssh_key_backup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
