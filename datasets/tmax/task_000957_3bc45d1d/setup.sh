#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy pandas

    mkdir -p /home/user/data
    mkdir -p /app

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import csv
import json
import random

random.seed(42)
categories = ['Electronics', 'Books', 'Clothing', 'Home', 'Toys']

with open('/home/user/data/products.csv', 'w', newline='') as f_csv, \
     open('/home/user/data/descriptions.json', 'w') as f_json:
    writer = csv.writer(f_csv)
    writer.writerow(['product_id', 'name', 'category'])
    for i in range(1, 10001):
        cat = random.choice(categories)
        name = f"Product_{i}"
        desc = f"This is a wonderful {cat.lower()} product with many great features. Id {i}."
        writer.writerow([i, name, cat])
        f_json.write(json.dumps({"id": i, "desc": desc}) + '\n')
EOF
    python3 /tmp/generate_data.py

    # Generate C++ binary
    cat << 'EOF' > /tmp/extractor.cpp
#include <iostream>
#include <string>
#include <vector>
#include <functional>

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        std::hash<std::string> hasher;
        size_t hash = hasher(line);
        std::vector<float> embedding(64);
        for (int i = 0; i < 64; ++i) {
            hash = hash * 1664525 + 1013904223;
            embedding[i] = (hash % 10000) / 10000.0f;
        }
        std::cout.write(reinterpret_cast<const char*>(embedding.data()), 64 * sizeof(float));
    }
    return 0;
}
EOF
    g++ -O3 -o /app/feature_extractor /tmp/extractor.cpp
    strip /app/feature_extractor

    # Cleanup
    rm /tmp/generate_data.py /tmp/extractor.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
