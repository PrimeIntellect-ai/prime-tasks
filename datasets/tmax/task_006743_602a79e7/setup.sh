#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy scipy

    mkdir -p /home/user
    cd /home/user

    # Create mock data generator
    cat << 'EOF' > generate_data.py
import random
import csv

random.seed(42)

def make_csv(filename, start_id, end_id, base_loss):
    with open(filename, 'w') as f:
        f.write("experiment_id,loss_score\n")
        for i in range(start_id, end_id):
            loss = base_loss + random.gauss(0, 2.0)
            f.write(f"{i},{loss:.4f}\n")

make_csv('train_metrics.csv', 1, 101, 10.0)
make_csv('test_metrics.csv', 101, 151, 12.0)

with open('metadata.csv', 'w') as f:
    f.write("experiment_id,duration_seconds\n")
    for i in range(1, 151):
        f.write(f"{i},{random.randint(60, 3600)}\n")
EOF
    python3 generate_data.py

    # Create buggy C++ pipeline
    cat << 'EOF' > etl_pipeline.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <numeric>
#include <cmath>
#include <map>
#include <sstream>
#include <iomanip>

struct Record {
    int id;
    double loss;
    int duration;
};

std::vector<Record> read_and_join(const std::string& metrics_file, const std::map<int, int>& metadata) {
    std::vector<Record> records;
    std::ifstream file(metrics_file);
    std::string line;
    std::getline(file, line); // skip header
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string id_str, loss_str;
        std::getline(ss, id_str, ',');
        std::getline(ss, loss_str, ',');
        int id = std::stoi(id_str);
        if (metadata.count(id)) {
            records.push_back({id, std::stod(loss_str), metadata.at(id)});
        }
    }
    return records;
}

int main() {
    std::map<int, int> metadata;
    std::ifstream meta_file("/home/user/metadata.csv");
    std::string line;
    std::getline(meta_file, line);
    while (std::getline(meta_file, line)) {
        std::stringstream ss(line);
        std::string id_str, dur_str;
        std::getline(ss, id_str, ',');
        std::getline(ss, dur_str, ',');
        metadata[std::stoi(id_str)] = std::stoi(dur_str);
    }

    auto train = read_and_join("/home/user/train_metrics.csv", metadata);
    auto test = read_and_join("/home/user/test_metrics.csv", metadata);

    // BUG: Data Leak
    std::vector<double> all_losses;
    for (const auto& r : train) all_losses.push_back(r.loss);
    for (const auto& r : test) all_losses.push_back(r.loss);

    double sum = std::accumulate(all_losses.begin(), all_losses.end(), 0.0);
    double mean = sum / all_losses.size();

    double sq_sum = std::accumulate(all_losses.begin(), all_losses.end(), 0.0,
        [mean](double acc, double val) { return acc + (val - mean) * (val - mean); });
    double stddev = std::sqrt(sq_sum / all_losses.size());

    // Normalization logic goes here...

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
