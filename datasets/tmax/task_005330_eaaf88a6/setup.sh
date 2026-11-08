#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /app/edge-aggregator-1.0
mkdir -p /home/user/ota_payload/etc

cat << 'EOF' > /app/edge-aggregator-1.0/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -O0 -Wall

all:
	$(CXX) $(CXXFLAGS) main.cpp -o /home/user/edge-aggregator
EOF

cat << 'EOF' > /app/edge-aggregator-1.0/main.cpp
#include <iostream>
#include <fstream>
#include <string_view>
#include <filesystem>

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    std::filesystem::path p(argv[1]);
    if (!std::filesystem::exists(p)) return 1;
    std::ifstream file(argv[1]);
    std::ofstream out(argv[2]);
    std::string line;
    long long count = 0;
    while (std::getline(file, line)) {
        std::string_view sv(line);
        if (!sv.empty()) count++;
    }
    out << count << "\n";
    return 0;
}
EOF

cat << 'EOF' > /app/sample_sensors.csv
sensor_id,value,timestamp
s1,23.5,1678886400
s2,24.1,1678886401
s3,22.8,1678886402
EOF

touch /home/user/ota_payload/etc/fstab

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
