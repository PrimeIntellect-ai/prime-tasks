#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/service_a.log
[01:59:55] 10
[01:59:56] 10
[01:59:57] 10
[01:59:58] 10
[01:59:59] 10
[02:00:00] 500
[02:00:01] 10
[02:00:02] 10
[02:00:03] 10
[02:00:04] 10
[02:00:05] 20
[02:00:06] 20
[02:00:07] 20
[02:00:08] 20
[02:00:09] 20
EOF

    cat << 'EOF' > /home/user/aggregator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

int main() {
    std::ifstream infile("/home/user/logs/service_a.log");
    std::ofstream outfile("/home/user/logs/service_b_fixed.log");

    if (!infile.is_open() || !outfile.is_open()) {
        std::cerr << "Error opening files." << std::endl;
        return 1;
    }

    std::string ts;
    int val;
    std::vector<int> batch;
    std::string last_ts;

    while (infile >> ts >> val) {
        batch.push_back(val);
        last_ts = ts;

        if (batch.size() == 5) {
            int sum = 0;
            // BUG: off-by-one error, skips the first element
            for (size_t i = 1; i < batch.size(); i++) {
                sum += batch[i];
            }
            int avg = sum / 5;
            outfile << last_ts << " " << avg << "\n";
            batch.clear();
        }
    }

    infile.close();
    outfile.close();
    return 0;
}
EOF

    chown -R user:user /home/user/logs
    chown user:user /home/user/aggregator.cpp

    chmod -R 777 /home/user
