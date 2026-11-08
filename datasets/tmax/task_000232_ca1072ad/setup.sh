#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

# Create dataset A
with open('/home/user/dataset_A.csv', 'w') as f:
    f.write("id,val1\n")
    # Train set (1-80): mean 10.0
    for i in range(1, 81):
        if i == 1: val = 9.0
        elif i == 2: val = 11.0
        else: val = 10.0
        f.write(f"{i},{val}\n")
    # Test set (81-100): mean 50.0
    for i in range(81, 101):
        if i == 81: val = 49.0
        elif i == 82: val = 51.0
        else: val = 50.0
        f.write(f"{i},{val}\n")

# Create dataset B
with open('/home/user/dataset_B.csv', 'w') as f:
    f.write("id,val2\n")
    for i in range(1, 101):
        f.write(f"{i},5.0\n")

# Create buggy pipeline.cpp
cpp_code = """#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>

struct Row {
    int id;
    double val1;
    double val2;
    double prediction;
};

int main() {
    std::vector<Row> data(100);

    // Read A
    std::ifstream fileA("dataset_A.csv");
    std::string line;
    std::getline(fileA, line); // header
    int idx = 0;
    while(std::getline(fileA, line) && idx < 100) {
        std::stringstream ss(line);
        std::string item;
        std::getline(ss, item, ','); data[idx].id = std::stoi(item);
        std::getline(ss, item, ','); data[idx].val1 = std::stod(item);
        idx++;
    }

    // Read B
    std::ifstream fileB("dataset_B.csv");
    std::getline(fileB, line); // header
    idx = 0;
    while(std::getline(fileB, line) && idx < 100) {
        std::stringstream ss(line);
        std::string item;
        std::getline(ss, item, ','); 
        std::getline(ss, item, ','); data[idx].val2 = std::stod(item);
        idx++;
    }

    // DATA LEAK: Global mean calculation
    double sum = 0;
    for(int i=0; i<100; i++) sum += data[i].val1;
    double mean = sum / 100.0;

    for(int i=0; i<100; i++) data[i].val1 -= mean;

    // Inference on Test Set (last 20 rows)
    std::ofstream out("predictions.csv");
    out << "id,prediction\\n";
    for(int i=80; i<100; i++) {
        data[i].prediction = data[i].val1 * 2.0 + data[i].val2;
        out << data[i].id << "," << data[i].prediction << "\\n";
    }

    return 0;
}
"""

with open('/home/user/pipeline.cpp', 'w') as f:
    f.write(cpp_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
