#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/rotate_creds.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <openssl/sha.h>
#include <sys/prctl.h>
#include <linux/seccomp.h>
#include <unistd.h>

int main() {
    // TODO: Read config.json
    // TODO: Verify SHA256 matches config.json.sha256

    std::string master_key = "secR3t_k3Y_991"; // Example extraction
    bool admin_override = true;

    std::string new_cred;
    if (admin_override) {
        // Insecure bypass
        new_cred = "insecure_generated_cred";
    } else {
        // Secure derivation
        new_cred = master_key + "_ROTATED";
    }

    // TODO: Enable strict seccomp

    // Write new credential to new_creds.txt
    std::ofstream out("/home/user/app/new_creds.txt");
    out << new_cred;
    out.close();

    return 0;
}
EOF

    chmod -R 777 /home/user
