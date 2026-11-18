#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensor_1.txt
10.0
12.0
14.0
EOF

    cat << 'EOF' > /home/user/data/sensor_2.txt
100000000.1
100000000.2
100000000.3
EOF

    cat << 'EOF' > "/home/user/data/sensor 3.txt"
5.0
ERROR_NO_DATA
7.0
EOF

    cat << 'EOF' > /home/user/pipeline/run_all.sh
#!/bin/bash
g++ -O3 /home/user/pipeline/process.cpp -o /home/user/pipeline/process

rm -f /home/user/final_report.txt

# BUG: Breaks on spaces
for f in $(find /home/user/data -type f); do
    /home/user/pipeline/process $f >> /home/user/final_report.txt
done
EOF
    chmod +x /home/user/pipeline/run_all.sh

    cat << 'EOF' > /home/user/pipeline/process.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;

    std::string filepath = argv[1];
    std::string basename = filepath.substr(filepath.find_last_of("/\\") + 1);

    std::ifstream file(filepath);
    if (!file.is_open()) {
        std::cerr << "Could not open file: " << filepath << std::endl;
        return 1;
    }

    std::string line;
    float sum = 0.0f;
    float sum_sq = 0.0f;
    int count = 0;

    while (std::getline(file, line)) {
        if (line.empty()) continue;
        // BUG: Crashes on invalid argument
        float val = std::stof(line);

        // BUG: Naive variance with floats
        sum += val;
        sum_sq += val * val;
        count++;
    }

    if (count == 0) return 0;

    float mean = sum / count;
    float variance = (sum_sq / count) - (mean * mean);

    std::cout << "Filename: " << basename 
              << ", Mean: " << std::fixed << std::setprecision(4) << mean 
              << ", Variance: " << std::fixed << std::setprecision(4) << variance 
              << std::endl;

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
