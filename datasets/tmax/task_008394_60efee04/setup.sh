#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/service_a.log
TXN001 1715000000.121
TXN002 1715000005.402
TXN003 1715000010.881
EOF

    cat << 'EOF' > /home/user/logs/service_b.log
TXN001 1715000000.125
TXN002 1715000005.409
TXN003 1715000010.884
EOF

    cat << 'EOF' > /home/user/logs/service_c.log
TXN001 1715000000.129
TXN002 1715000005.415
TXN003 1715000010.890
EOF

    cat << 'EOF' > /home/user/aggregator.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <map>
#include <cassert>
#include <iomanip>
#include <algorithm>

struct Event {
    std::string txn_id;
    float timestamp; // BUG: precision loss
    std::string service;
};

void load_logs(const std::string& filename, const std::string& service, std::vector<Event>& events) {
    std::ifstream infile(filename);
    std::string txn_id;
    float ts; // BUG: precision loss
    while (infile >> txn_id >> ts) {
        events.push_back({txn_id, ts, service});
    }
}

int main() {
    std::vector<Event> all_events;
    load_logs("/home/user/logs/service_a.log", "ServiceA", all_events);
    load_logs("/home/user/logs/service_b.log", "ServiceB", all_events);
    load_logs("/home/user/logs/service_c.log", "ServiceC", all_events);

    // Group by TXN
    std::map<std::string, std::vector<Event>> txns;
    for (const auto& ev : all_events) {
        txns[ev.txn_id].push_back(ev);
    }

    std::ofstream outfile("/home/user/fixed_timeline.csv");
    outfile << "txn_id,duration\n";

    for (auto& pair : txns) {
        auto& evs = pair.second;
        // Sort by timestamp
        std::sort(evs.begin(), evs.end(), [](const Event& a, const Event& b){
            return a.timestamp < b.timestamp;
        });

        // Assertion-based intermediate validation
        for (size_t i = 1; i < evs.size(); ++i) {
            // Fails here because float precision merges the timestamps!
            assert(evs[i].timestamp > evs[i-1].timestamp && "Strict ordering failed due to identical timestamps!");
        }

        float duration = evs.back().timestamp - evs.front().timestamp;
        outfile << pair.first << "," << std::fixed << std::setprecision(3) << duration << "\n";
    }

    std::cout << "Successfully processed and validated logs.\n";
    return 0;
}
EOF

    chmod -R 777 /home/user
