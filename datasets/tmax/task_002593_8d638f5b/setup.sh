#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake
    pip3 install pytest

    mkdir -p /home/user/pipeline/data
    mkdir -p /home/user/pipeline/src
    mkdir -p /home/user/pipeline/output

    cat << 'EOF' > /home/user/pipeline/data/dataset.csv
id,feature_1,is_train
1,10.0,1
2,20.0,1
3,30.0,1
4,5.0,0
5,40.0,0
EOF

    cat << 'EOF' > /home/user/pipeline/src/normalize.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <limits>
#include <iomanip>

struct Row {
    int id;
    double feature_1;
    int is_train;
};

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <input.csv> <output.csv>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    std::string line;
    std::vector<Row> data;

    // Read header
    if (std::getline(infile, line)) {
        // Skip header
    }

    double global_min = std::numeric_limits<double>::max();
    double global_max = std::numeric_limits<double>::lowest();

    while (std::getline(infile, line)) {
        std::stringstream ss(line);
        std::string cell;
        Row r;

        std::getline(ss, cell, ','); r.id = std::stoi(cell);
        std::getline(ss, cell, ','); r.feature_1 = std::stod(cell);
        std::getline(ss, cell, ','); r.is_train = std::stoi(cell);

        // BUG: Computes min/max over all data (leakage!)
        if (r.feature_1 < global_min) global_min = r.feature_1;
        if (r.feature_1 > global_max) global_max = r.feature_1;

        data.push_back(r);
    }
    infile.close();

    // Print metrics (incorrect global metrics)
    std::cout << "Feature 1: min=" << global_min << ", max=" << global_max << "\n";

    std::ofstream outfile(argv[2]);
    outfile << "id,feature_1_scaled,is_train\n";
    outfile << std::fixed << std::setprecision(4);

    for (const auto& r : data) {
        double scaled = (r.feature_1 - global_min) / (global_max - global_min);
        outfile << r.id << "," << scaled << "," << r.is_train << "\n";
    }
    outfile.close();

    return 0;
}
EOF

    cat << 'EOF' > /home/user/pipeline/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(DataPipeline)

set(CMAKE_CXX_STANDARD 17)

add_executable(normalize_tool src/normalize.cpp)
EOF

    cat << 'EOF' > /home/user/pipeline/run_experiment.sh
#!/bin/bash
# TODO: Run the C++ pipeline tool and log metrics
EOF
    chmod +x /home/user/pipeline/run_experiment.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
