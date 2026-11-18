#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/logs /home/user/src /home/user/bin

    cat << 'EOF' > /home/user/logs/batch_1.csv
10.5
11.2
10.8
11.0
10.9
EOF

    cat << 'EOF' > /home/user/logs/batch_2.csv
5.1
5.2
5.1
5.3
5.2
EOF

    cat << 'EOF' > /home/user/logs/batch_3.csv
10000000.1
10000000.2
10000000.1
10000000.3
10000000.2
EOF

    cat << 'EOF' > /home/user/logs/batch_4.csv
20.1
20.5
20.3
20.2
EOF

    cat << 'EOF' > /home/user/src/sensor_aggregator.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <stdexcept>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <logfile>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    std::vector<float> values;
    float val;
    while (infile >> val) {
        values.push_back(val);
    }

    if (values.empty()) return 0;

    float sum = 0.0f;
    float sum_sq = 0.0f;
    for (float v : values) {
        sum += v;
        sum_sq += v * v;
    }

    float mean = sum / values.size();
    float variance = (sum_sq / values.size()) - (mean * mean);

    if (variance < 0.0f) {
        // Due to precision issues with naive variance, variance might be negative
        throw std::runtime_error("Domain error: variance is negative (" + std::to_string(variance) + ")");
    }

    float stddev = std::sqrt(variance);

    std::cout << "File: " << argv[1] << " | Mean: " << std::fixed << std::setprecision(2) << mean << " | StdDev: " << stddev << "\n";

    return 0;
}
EOF

    g++ -O2 /home/user/src/sensor_aggregator.cpp -o /home/user/bin/sensor_aggregator

    cat << 'EOF' > /home/user/run_pipeline.sh
#!/bin/bash

for f in /home/user/logs/*.csv; do
    /home/user/bin/sensor_aggregator "$f"
done
EOF
    chmod +x /home/user/run_pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
