#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
id,f1,f2
101,2.0,4.0
101,4.0,6.0
102,1.0,2.0
102,3.0,0.0
103,10.0,10.0
104,0.0,0.0
EOF

    cat << 'EOF' > /home/user/etl.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <map>
#include <vector>
#include <iomanip>

struct Features {
    double f1_sum = 0.0;
    double f2_sum = 0.0;
    int count = 0;
};

int main() {
    std::ifstream infile("/home/user/data.csv");
    std::string line;

    // Skip header
    std::getline(infile, line);

    std::map<int, Features> data_map;

    while (std::getline(infile, line)) {
        std::stringstream ss(line);
        std::string token;

        std::getline(ss, token, ',');
        int id = std::stoi(token);

        std::getline(ss, token, ',');
        double f1 = std::stod(token);

        std::getline(ss, token, ',');
        double f2 = std::stod(token);

        data_map[id].f1_sum += f1;
        data_map[id].f2_sum += f2;
        data_map[id].count += 1;
    }

    std::ofstream outfile("/home/user/predictions.csv");
    outfile << "id,prediction\n";

    // Model weights
    double w1 = 1 / 2; // BUG: Integer division, evaluates to 0.0
    double w2 = 1.2;
    double bias = 0.1;

    for (auto const& [id, feats] : data_map) {
        // BUG: Using sums instead of means
        double mean_f1 = feats.f1_sum; 
        double mean_f2 = feats.f2_sum;

        double prediction = (mean_f1 * w1) + (mean_f2 * w2) + bias;

        outfile << id << "," << std::fixed << std::setprecision(1) << prediction << "\n";
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
