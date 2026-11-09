#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/seq.cpp
#include <iostream>
#include <string>
#include <vector>
#include <cmath>
#include <algorithm>

void get_distribution(const std::string& seq, int start, int end, double* dist) {
    for (int i = 0; i < 4; ++i) dist[i] = 0.0;
    if (start >= end) return;
    int counts[4] = {0, 0, 0, 0};
    for (int i = start; i < end; ++i) {
        if (seq[i] == 'A') counts[0]++;
        else if (seq[i] == 'C') counts[1]++;
        else if (seq[i] == 'G') counts[2]++;
        else if (seq[i] == 'T') counts[3]++;
    }
    double len = end - start;
    for (int i = 0; i < 4; ++i) dist[i] = counts[i] / len;
}

void split_domain(const std::string& seq, int start, int end, std::vector<int>& boundaries) {
    if (end - start < 10) return;

    int mid = start + (end - start) / 2;

    double dist_left[4];
    double dist_right[4];

    get_distribution(seq, start, mid, dist_left);
    get_distribution(seq, mid, end, dist_right);

    double l1_distance = 0.0;
    for (int i = 0; i < 4; ++i) {
        l1_distance += std::abs(dist_left[i] - dist_right[i]);
    }

    if (l1_distance > 0.40) {
        split_domain(seq, start, mid, boundaries);
        boundaries.push_back(mid);
        split_domain(seq, mid, end, boundaries);
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::string seq = argv[1];
    std::vector<int> boundaries;

    split_domain(seq, 0, seq.length(), boundaries);

    std::sort(boundaries.begin(), boundaries.end());

    for (size_t i = 0; i < boundaries.size(); ++i) {
        std::cout << boundaries[i] << (i == boundaries.size() - 1 ? "" : ",");
    }
    std::cout << std::endl;

    return 0;
}
EOF

    g++ -O2 /tmp/seq.cpp -o /app/seq_domain_splitter
    strip /app/seq_domain_splitter
    rm /tmp/seq.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
