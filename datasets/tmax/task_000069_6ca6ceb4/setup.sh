#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/service_a.log
1000,TX01,START
1010,TX02,START
1020,TX03,START
1030,TX04,START
1040,TX05,START
1050,TX06,START
EOF

    cat << 'EOF' > /home/user/service_b.log
1005,TX01,PROCESS
1015,TX02,PROCESS
1025,TX03,PROCESS
1035,TX04,PROCESS
1030,TX05,PROCESS
1060,TX06,PROCESS
EOF

    cat << 'EOF' > /home/user/service_c.log
1010,TX01,END
1020,TX02,END
1040,TX04,END
1050,TX05,END
1055,TX06,END
EOF

    cat << 'EOF' > /home/user/analyzer.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <optional>
#include <vector>
#include <algorithm>

struct Transaction {
    std::string id;
    std::optional<long> time_a;
    std::optional<long> time_b;
    std::optional<long> time_c;
};

void parse_log(const std::string& filename, std::unordered_map<std::string, Transaction>& txs, int service_idx) {
    std::ifstream file(filename);
    std::string line;
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string time_str, id, status;
        std::getline(ss, time_str, ',');
        std::getline(ss, id, ',');
        std::getline(ss, status, ',');
        if (time_str.empty()) continue;
        long time_val = std::stol(time_str);
        if (service_idx == 0) txs[id].time_a = time_val;
        if (service_idx == 1) txs[id].time_b = time_val;
        if (service_idx == 2) txs[id].time_c = time_val;
        txs[id].id = id;
    }
}

int main() {
    std::unordered_map<std::string, Transaction> txs;
    parse_log("/home/user/service_a.log", txs, 0);
    parse_log("/home/user/service_b.log", txs, 1);
    parse_log("/home/user/service_c.log", txs, 2);

    int total = txs.size();
    int converged = 0;
    std::vector<std::string> failed;
    std::vector<std::string> violations;

    for (const auto& pair : txs) {
        const auto& tx = pair.second;
        // BUG: blindly unwrap
        long a = tx.time_a.value();
        long b = tx.time_b.value();
        long c = tx.time_c.value();

        converged++;
    }

    // Agent must add code to write to /home/user/report.txt
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
