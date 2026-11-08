#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    mkdir -p /home/user/suspicious/subdir
    touch /home/user/suspicious/normal_file.txt
    touch /home/user/suspicious/suid_bin
    touch /home/user/suspicious/subdir/world_write.conf

    mkdir -p /home/user/log_analyzer/src /home/user/log_analyzer/bin /home/user/data

    cat << 'EOF' > /home/user/log_analyzer/src/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

// TODO: Fix this code to validate cert chains and redact 16-digit numbers.
int main() {
    std::ifstream infile("/home/user/data/input.log");
    std::ofstream outfile("/home/user/data/clean_output.log");
    std::string line;
    while (std::getline(infile, line)) {
        outfile << line << "\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data/input.log
[INFO] CHAIN: Client1|IntCA1, IntCA1|RootCA MESSAGE: User 1234123412341234 logged in.
[INFO] CHAIN: Client2|IntCA2, IntCA3|RootCA MESSAGE: User 5555666677778888 failed.
[INFO] CHAIN: Client3|RootCA MESSAGE: Payment 9999888877776666 done.
[INFO] CHAIN: Client4|IntCA4, IntCA4|IntCA5, IntCA5|RootCA MESSAGE: Card 1111222233334444 approved.
[INFO] CHAIN: Client5|RootCB MESSAGE: Attempted payment 5555555555555555.
EOF

    chmod -R 777 /home/user

    # Restore specific permissions required by the task
    chmod 4755 /home/user/suspicious/suid_bin
    chmod 666 /home/user/suspicious/subdir/world_write.conf
