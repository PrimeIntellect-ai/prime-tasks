#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_engine.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <unordered_map>
#include <algorithm>

struct Node {
    int id;
    std::string type;
    double weight;
};

struct Result {
    int u_id;
    int p_id;
    int c_id;
    double p_weight;
};

int main(int argc, char* argv[]) {
    if (argc != 5) return 1;
    std::string edges_file = argv[1];
    std::string nodes_file = argv[2];
    int offset = std::stoi(argv[3]);
    int limit = std::stoi(argv[4]);

    std::unordered_map<int, Node> nodes;
    std::ifstream nf(nodes_file);
    std::string line;
    if (std::getline(nf, line)) {
        while (std::getline(nf, line)) {
            if (line.empty()) continue;
            std::stringstream ss(line);
            std::string id_s, type, weight_s;
            std::getline(ss, id_s, ',');
            std::getline(ss, type, ',');
            std::getline(ss, weight_s, ',');
            nodes[std::stoi(id_s)] = {std::stoi(id_s), type, std::stod(weight_s)};
        }
    }

    std::unordered_map<int, std::vector<int>> buys;
    std::unordered_map<int, std::vector<int>> belongs_to;

    std::ifstream ef(edges_file);
    if (std::getline(ef, line)) {
        while (std::getline(ef, line)) {
            if (line.empty()) continue;
            std::stringstream ss(line);
            std::string src_s, tgt_s, type;
            std::getline(ss, src_s, ',');
            std::getline(ss, tgt_s, ',');
            std::getline(ss, type, ',');
            int src = std::stoi(src_s);
            int tgt = std::stoi(tgt_s);
            if (type == "BUYS") buys[src].push_back(tgt);
            else if (type == "BELONGS_TO") belongs_to[src].push_back(tgt);
        }
    }

    std::vector<Result> results;
    for (const auto& kv : buys) {
        int u_id = kv.first;
        if (nodes.find(u_id) == nodes.end() || nodes[u_id].type != "User" || nodes[u_id].weight <= 10.0) continue;
        for (int p_id : kv.second) {
            if (nodes.find(p_id) == nodes.end() || nodes[p_id].type != "Product" || nodes[p_id].weight >= 50.0) continue;
            if (belongs_to.find(p_id) != belongs_to.end()) {
                for (int c_id : belongs_to[p_id]) {
                    if (nodes.find(c_id) != nodes.end() && nodes[c_id].type == "Category") {
                        results.push_back({u_id, p_id, c_id, nodes[p_id].weight});
                    }
                }
            }
        }
    }

    std::sort(results.begin(), results.end(), [](const Result& a, const Result& b) {
        if (a.c_id != b.c_id) return a.c_id > b.c_id;
        if (a.p_weight != b.p_weight) return a.p_weight < b.p_weight;
        return a.u_id < b.u_id;
    });

    std::cout << "user_id,product_id,category_id\n";
    int start = std::min(offset, (int)results.size());
    int end = std::min(offset + limit, (int)results.size());
    for (int i = start; i < end; ++i) {
        std::cout << results[i].u_id << "," << results[i].p_id << "," << results[i].c_id << "\n";
    }

    return 0;
}
EOF

    g++ -O3 -std=c++11 /app/legacy_engine.cpp -o /app/legacy_engine
    strip /app/legacy_engine
    rm /app/legacy_engine.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
