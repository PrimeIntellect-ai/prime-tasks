#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Generate the deterministic dataset.csv
cat << 'EOF' > /home/user/generate_csv.py
with open('/home/user/dataset.csv', 'w') as f:
    f.write('id,value\n')
    for i in range(1, 1001):
        # Deterministic values for simple verification
        f.write(f'{i},{i * 1.5}\n')
EOF
python3 /home/user/generate_csv.py
rm /home/user/generate_csv.py

# Create the buggy process.cpp
cat << 'EOF' > /home/user/process.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <cmath>

struct Record { int id; double value; };

int main() {
    std::ifstream in("/home/user/dataset.csv");
    std::vector<Record> data;
    std::string line;
    std::getline(in, line); // skip header
    while(std::getline(in, line)) {
        if(line.empty()) continue;
        std::stringstream ss(line);
        std::string id_s, val_s;
        std::getline(ss, id_s, ',');
        std::getline(ss, val_s, ',');
        data.push_back({std::stoi(id_s), std::stod(val_s)});
    }

    // BUG: Calculating stats on the whole dataset
    double sum = 0;
    for(size_t i=0; i<data.size(); ++i) {
        sum += data[i].value;
    }
    double mean = sum / data.size();

    double sq_sum = 0;
    for(size_t i=0; i<data.size(); ++i) {
        sq_sum += (data[i].value - mean)*(data[i].value - mean);
    }
    double stddev = std::sqrt(sq_sum / data.size());

    std::ofstream train("/home/user/train.csv");
    std::ofstream test("/home/user/test.csv");
    train << "id,normalized_value\n";
    test << "id,normalized_value\n";

    for(size_t i=0; i<data.size(); ++i) {
        double norm = (data[i].value - mean) / stddev;
        if (i < 800) {
            train << data[i].id << "," << norm << "\n";
        } else {
            test << data[i].id << "," << norm << "\n";
        }
    }
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
