#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/container_logs/app_prod
    cat << 'EOF' > /home/user/container_logs/app_prod/health.log
TOTAL_TIME 10000000
UPTIME 9999500
EOF

    cat << 'EOF' > /home/user/run_monitor.sh
#!/bin/bash
# Environment misconfiguration: points to wrong directory
export UPTIME_LOG_DIR="/var/log/containers/app"
/home/user/uptime_monitor
EOF
    chmod +x /home/user/run_monitor.sh

    cat << 'EOF' > /home/user/uptime_monitor.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <iomanip>
#include <cstdlib>

int main() {
    const char* log_dir = std::getenv("UPTIME_LOG_DIR");
    if (!log_dir) {
        std::cerr << "UPTIME_LOG_DIR not set!" << std::endl;
        return 1;
    }

    std::string filepath = std::string(log_dir) + "/health.log";
    std::ifstream infile(filepath);
    if (!infile.is_open()) {
        std::cerr << "Failed to open log file at " << filepath << std::endl;
        return 1;
    }

    std::string key;
    long long total_time = 0;
    long long uptime = 0;

    while (infile >> key) {
        if (key == "TOTAL_TIME") {
            infile >> total_time;
        } else if (key == "UPTIME") {
            infile >> uptime;
        }
    }

    if (total_time == 0) {
        std::cerr << "Total time is zero!" << std::endl;
        return 1;
    }

    // Precision loss bug here: integer division
    double percentage = (uptime / total_time) * 100.0;

    std::cout << "System Uptime: " << std::fixed << std::setprecision(4) << percentage << "%" << std::endl;

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
