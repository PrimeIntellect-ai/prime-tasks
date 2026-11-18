#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,category,measurement
1,A,10.5
2,B,-999.0
3,A,12.0
4,C,15.1
5,B,8.2
6,A,-999.0
7,C,14.0
8,B,9.1
9,A,11.5
10,C,-999.0
EOF

    awk 'BEGIN {
        srand(42);
        for(i=11; i<=1000; i++) {
            cat = (i%3==0) ? "A" : ((i%3==1) ? "B" : "C");
            if (rand() < 0.1) {
                val = "-999.0";
            } else {
                val = sprintf("%.1f", 10 + (rand() * 10 - 5));
            }
            printf "%d,%s,%s\n", i, cat, val;
        }
    }' >> /home/user/dataset.csv

    cat << 'EOF' > /home/user/data_processor.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <sstream>
#include <iomanip>

struct Row {
    int id;
    std::string category;
    double measurement;
};

int main() {
    std::vector<Row> data;
    std::ifstream file("/home/user/dataset.csv");
    std::string line, header;

    if (std::getline(file, header)) {
        while (std::getline(file, line)) {
            std::stringstream ss(line);
            std::string id_s, cat_s, meas_s;
            std::getline(ss, id_s, ',');
            std::getline(ss, cat_s, ',');
            std::getline(ss, meas_s, ',');
            data.push_back({std::stoi(id_s), cat_s, std::stod(meas_s)});
        }
    }

    // BUG: Calculating stats on entire dataset
    double sum = 0.0;
    int count = 0;
    for (const auto& r : data) {
        if (r.measurement != -999.0) {
            sum += r.measurement;
            count++;
        }
    }
    double mean = sum / count;

    double sq_sum = 0.0;
    for (const auto& r : data) {
        if (r.measurement != -999.0) {
            sq_sum += (r.measurement - mean) * (r.measurement - mean);
        }
    }
    double std_dev = std::sqrt(sq_sum / count);

    // Impute and normalize
    for (auto& r : data) {
        if (r.measurement == -999.0) {
            r.measurement = mean;
        }
        r.measurement = (r.measurement - mean) / std_dev;
    }

    // Split and write
    auto write_csv = [](const std::string& path, const std::vector<Row>& rows, int start, int end) {
        std::ofstream out(path);
        out << "id,category,measurement\n";
        for (int i = start; i < end; ++i) {
            out << rows[i].id << "," << rows[i].category << "," 
                << std::fixed << std::setprecision(4) << rows[i].measurement << "\n";
        }
    };

    write_csv("/home/user/train_clean.csv", data, 0, 800);
    write_csv("/home/user/test_clean.csv", data, 800, 1000);

    return 0;
}
EOF

    chmod -R 777 /home/user
