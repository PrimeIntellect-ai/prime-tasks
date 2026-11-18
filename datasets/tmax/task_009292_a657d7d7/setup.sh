#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ logrotate
pip3 install pytest

mkdir -p /home/user/logs

cat << 'EOF' > /home/user/raw_build.txt
[CI] Build initialized
[DEBUG] Checking environment variables
[CI] ERROR: Missing provisioning credentials
[INFO] Attempting fallback routine
[CI] Build process terminated early
EOF

cat << 'EOF' > /home/user/ci_logger.cpp
#include <iostream>
#include <fstream>
#include <string>

int main() {
    std::string line;
    std::ofstream logfile("/home/user/logs/ci_build.log", std::ios::app);

    if (!logfile.is_open()) {
        std::cerr << "Failed to open log file." << std::endl;
        return 1;
    }

    while (std::getline(std::cin, line)) {
        // BUG: Silently drop FATAL lines
        if (line.find("FATAL") != std::string::npos) {
            continue;
        }
        logfile << line << "\n";
    }

    logfile.close();
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
