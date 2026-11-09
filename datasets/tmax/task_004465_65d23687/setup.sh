#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/auth_system

    cat << 'EOF' > /home/user/auth_system/auth_logger.cpp
#include <iostream>
#include <string>
#include <fstream>

bool check_pin(int pin) {
    // Custom "secure" hash
    unsigned int hash = (pin * 1337) ^ 0xDEADBEEF;
    return hash == 3730533034; // 0xDE6020AA
}

void log_attempt(int pin, bool success) {
    std::ofstream logfile("audit.log", std::ios_base::app);
    if (success) {
        logfile << "[INFO] Successful login." << std::endl;
    } else {
        // VULNERABILITY: Logging plaintext PIN
        logfile << "[ERROR] Invalid attempt with PIN: " << pin << std::endl;
    }
}

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    int pin = std::stoi(argv[1]);
    bool valid = check_pin(pin);
    log_attempt(pin, valid);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/auth_system/old_logs.txt
[INFO] System started at 08:00
[INFO] User admin logged in
[ERROR] Invalid attempt with PIN: 1234
[ERROR] Connection timeout from 192.168.1.50
[ERROR] Invalid attempt with PIN: 9999
[ERROR] Invalid attempt with PIN: 0042
[INFO] Daily backup completed. PIN: 1234 was used for backup auth? No.
[ERROR] Invalid attempt with PIN: 5555
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
