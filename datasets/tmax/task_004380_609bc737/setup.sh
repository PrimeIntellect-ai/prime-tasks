#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl wget
    pip3 install pytest

    # Create the legacy archiver
    mkdir -p /app
    cat << 'EOF' > /tmp/archiver.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <filesystem>
#include <vector>

namespace fs = std::filesystem;

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    std::string dir = argv[1];
    std::string dat_path = argv[2];
    std::string csv_path = argv[3];

    std::ofstream dat(dat_path, std::ios::binary);
    std::ofstream csv(csv_path);

    long offset = 0;
    for (const auto& entry : fs::directory_iterator(dir)) {
        if (entry.is_regular_file()) {
            std::string filename = entry.path().filename().string();
            std::ifstream in(entry.path(), std::ios::binary);
            std::vector<char> buffer((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
            long length = buffer.size();
            csv << filename << "," << offset << "," << length << "\n";
            for (char& c : buffer) {
                c ^= 0x5A;
            }
            dat.write(buffer.data(), buffer.size());
            offset += length;
        }
    }
    return 0;
}
EOF
    g++ -O2 -std=c++17 /tmp/archiver.cpp -o /app/legacy_archiver
    strip /app/legacy_archiver
    rm /tmp/archiver.cpp

    # Create backup config
    cat << 'EOF' > /etc/backup_config.json
{
    "archive_path": "/var/backups/production.dat",
    "index_path": "/var/backups/production.csv",
    "port": 9000
}
EOF

    # Generate production archives
    mkdir -p /var/backups
    mkdir -p /tmp/prod_data
    echo "This is a secret report. Do not share." > /tmp/prod_data/secret_report.txt
    echo "System log entries..." > /tmp/prod_data/syslog.bak
    /app/legacy_archiver /tmp/prod_data /var/backups/production.dat /var/backups/production.csv
    rm -rf /tmp/prod_data

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
