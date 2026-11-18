#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import random
with open('/home/user/features.csv', 'w') as f:
    f.write("id,age,income\n")
    for i in range(1, 101):
        f.write(f"{i},{20 + (i%30)},{40000 + (i*1000)}\n")

with open('/home/user/embeddings.csv', 'w') as f:
    f.write("id,emb1,emb2\n")
    for i in range(1, 101):
        f.write(f"{i},{i*0.1:.1f},{-i*0.1:.1f}\n")
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    cat << 'EOF' > /home/user/pipeline.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <map>
#include <random>

struct Record {
    std::string id;
    std::string features;
    std::string embeddings;
};

int main() {
    std::map<std::string, std::string> features_map;
    std::ifstream feat_file("/home/user/features.csv");
    std::string line, id, rest;

    // Read features
    if (std::getline(feat_file, line)) { /* skip header */ }
    while (std::getline(feat_file, line)) {
        std::stringstream ss(line);
        std::getline(ss, id, ',');
        std::getline(ss, rest);
        features_map[id] = rest;
    }

    std::vector<Record> joined_data;
    std::ifstream emb_file("/home/user/embeddings.csv");

    // Read embeddings (BUG: split by space instead of comma)
    if (std::getline(emb_file, line)) { /* skip header */ }
    while (std::getline(emb_file, line)) {
        std::stringstream ss(line);
        std::getline(ss, id, ' '); // BUG: should be ','
        std::getline(ss, rest);

        if (features_map.count(id)) {
            joined_data.push_back({id, features_map[id], rest});
        }
    }

    if (joined_data.empty()) {
        std::cerr << "Joined data is empty!" << std::endl;
        return 1;
    }

    // Sampling (BUG: non-deterministic seed, using uniform_int_distribution)
    std::random_device rd;
    std::mt19937 gen(rd()); // BUG: needs to be fixed to 42

    std::ofstream out_file("/home/user/sampled_data.csv");
    out_file << "id,features,embeddings\n";
    for (int i = 0; i < 50; ++i) {
        // BUG: requested to use gen() % joined_data.size() directly
        std::uniform_int_distribution<> dis(0, joined_data.size() - 1);
        size_t idx = dis(gen);
        out_file << joined_data[idx].id << "," << joined_data[idx].features << "," << joined_data[idx].embeddings << "\n";
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
