#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils gawk
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/csv_processor.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <iomanip>

struct GroupData {
    std::string department;
    double profit = 0;
    int count = 0;
};

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1]);
    std::string line;
    std::getline(file, line); // skip header
    std::map<std::string, GroupData> groups;
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string id, dept, status, rev_s, cost_s, ts;
        std::getline(ss, id, ',');
        std::getline(ss, dept, ',');
        std::getline(ss, status, ',');
        std::getline(ss, rev_s, ',');
        std::getline(ss, cost_s, ',');
        std::getline(ss, ts, ',');

        if (status == "ACTIVE") {
            double rev = std::stod(rev_s);
            double cost = std::stod(cost_s);
            if (rev - cost > 0) {
                groups[dept].department = dept;
                groups[dept].profit += (rev - cost);
                groups[dept].count += 1;
            }
        }
    }

    std::vector<GroupData> results;
    for (auto const& [key, val] : groups) {
        results.push_back(val);
    }

    std::sort(results.begin(), results.end(), [](const GroupData& a, const GroupData& b) {
        if (std::abs(a.profit - b.profit) > 1e-9) {
            return a.profit > b.profit;
        }
        return a.department < b.department;
    });

    int limit = std::min(5, (int)results.size());
    for (int i = 0; i < limit; ++i) {
        std::cout << "Department: " << results[i].department 
                  << " | Profit: " << std::fixed << std::setprecision(2) << results[i].profit 
                  << " | Count: " << results[i].count << std::endl;
    }
    return 0;
}
EOF

    g++ -O3 /app/csv_processor.cpp -o /app/csv_processor
    strip /app/csv_processor
    rm /app/csv_processor.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
