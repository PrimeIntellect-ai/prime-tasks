#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest pandas numpy

    mkdir -p /app
    cat << 'EOF' > /app/leaky_target_encoder.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>

using namespace std;

struct Row { string id; string cat; double target; };

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    ifstream in(argv[1]);
    ofstream out(argv[2]);
    string line, id, cat, target_str;
    vector<Row> rows;
    double sum = 0;
    int count = 0;
    unordered_map<string, double> cat_sum;
    unordered_map<string, int> cat_count;

    getline(in, line); // header
    while (getline(in, line)) {
        stringstream ss(line);
        getline(ss, id, ',');
        getline(ss, cat, ',');
        getline(ss, target_str, ',');
        double t = stod(target_str);
        rows.push_back({id, cat, t});
        sum += t; count++;
        cat_sum[cat] += t;
        cat_count[cat]++;
    }

    double global_mean = count > 0 ? sum / count : 0;
    double m = 15.0; // The hidden parameter

    out << "id,encoded_target\n";
    for (auto& r : rows) {
        double c_mean = cat_sum[r.cat] / cat_count[r.cat];
        double n = cat_count[r.cat];
        double enc = (n * c_mean + m * global_mean) / (n + m);
        out << r.id << "," << enc << "\n";
    }
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/leaky_target_encoder.cpp -o /app/leaky_target_encoder
    strip /app/leaky_target_encoder
    rm /app/leaky_target_encoder.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
