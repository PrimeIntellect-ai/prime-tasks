#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/pipeline

# 1. Create the dataset
cat << 'EOF' > /home/user/pipeline/data.csv
id,feature,target
1,12.5,25.0
2,14.2,28.4
3,1000.0,0.0
4,13.1,26.2
5,-500.0,0.0
6,15.0,30.0
7,11.8,23.6
8,14.5,29.0
EOF

# 2. Create the buggy C++ code
cat << 'EOF' > /home/user/pipeline/cleaner.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <cstdlib>
#include <cmath>

struct Record {
    int id;
    double feature;
    double target;
};

int main() {
    const char* path = std::getenv("DATASET_PATH");
    if (!path) {
        std::cerr << "Error: DATASET_PATH not set.\n";
        return 1;
    }

    std::ifstream file(path);
    if (!file.is_open()) return 1;

    std::string line;
    std::getline(file, line); // skip header

    std::vector<Record> records;
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string val;
        Record r;
        std::getline(ss, val, ','); r.id = std::stoi(val);
        std::getline(ss, val, ','); r.feature = std::stod(val);
        std::getline(ss, val, ','); r.target = std::stod(val);
        records.push_back(r);
    }

    if (records.empty()) return 1;

    // Bootstrap sampling for mean
    std::srand(42);
    int num_samples = 1000;
    int total_sum = 0; // BUG: Should be double

    for (int i = 0; i < num_samples; ++i) {
        int idx = std::rand() % records.size();
        total_sum += records[idx].feature; 
    }

    double mean = total_sum / num_samples; // BUG: Integer division + integer sum overflow/truncation

    std::vector<Record> cleaned;
    for (const auto& r : records) {
        if (std::abs(r.feature - mean) <= 10.0) {
            cleaned.push_back(r);
        }
    }

    if (cleaned.empty()) {
        std::cerr << "0 valid records\n";
        std::ofstream out("/home/user/pipeline/model_params.txt");
        out << "";
        return 1;
    }

    // Simple Linear Regression: target = m * feature + c
    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;
    for (const auto& r : cleaned) {
        sum_x += r.feature;
        sum_y += r.target;
        sum_xy += r.feature * r.target;
        sum_xx += r.feature * r.feature;
    }

    double n = cleaned.size();
    double m = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x);
    double c = (sum_y - m * sum_x) / n;

    std::ofstream out("/home/user/pipeline/model_params.txt");
    out << "m=" << m << ",c=" << c << "\n";

    return 0;
}
EOF

# 3. Create the buggy bash script
cat << 'EOF' > /home/user/pipeline/run_pipeline.sh
#!/bin/bash
cd /home/user/pipeline
g++ -O3 cleaner.cpp -o cleaner
./cleaner 2>/dev/null
EOF
chmod +x /home/user/pipeline/run_pipeline.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
