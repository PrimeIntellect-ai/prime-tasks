#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ gawk
pip3 install pytest

mkdir -p /home/user/src
mkdir -p /home/user/real_data/input
echo "Test data to process" > /home/user/real_data/input/data1.txt

cat << 'EOF' > /home/user/pseudo_fstab
/home/user/real_data/input /home/user/app/input
/home/user/real_data/output /home/user/app/output
/home/user/real_data/logs /home/user/app/logs
EOF

cat << 'EOF' > /home/user/src/processor.cpp
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <string>

int main() {
    // BUG: Hardcoded path requiring root
    std::string log_path = "/var/log/processor.log";
    std::ofstream log_file(log_path, std::ios::app);

    if (!log_file.is_open()) {
        std::cerr << "Failed to open log file." << std::endl;
        return 1;
    }

    const char* in_dir = std::getenv("IN_DIR");
    const char* out_dir = std::getenv("OUT_DIR");

    if (!in_dir || !out_dir) {
        log_file << "ERROR: IN_DIR or OUT_DIR not set." << std::endl;
        return 1;
    }

    log_file << "INFO: Starting processing." << std::endl;
    log_file << "ERROR: Mock error for log testing." << std::endl;

    std::string in_file = std::string(in_dir) + "/data1.txt";
    std::string out_file = std::string(out_dir) + "/data1.txt.out";

    std::ifstream is(in_file);
    if (!is.is_open()) {
        log_file << "ERROR: Could not read input file." << std::endl;
        return 1;
    }

    std::string content;
    std::getline(is, content);
    is.close();

    std::ofstream os(out_file);
    os << content << " - PROCESSED";
    os.close();

    log_file << "INFO: Finished successfully." << std::endl;
    return 0;
}
EOF

cat << 'EOF' > /home/user/service_manager.sh
#!/usr/bin/env bash
# Simulates a stripped-down environment (like cron)
env -i bash -c '/home/user/app/bin/processor'
EOF
chmod +x /home/user/service_manager.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
