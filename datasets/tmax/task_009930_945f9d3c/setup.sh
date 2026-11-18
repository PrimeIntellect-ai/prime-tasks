#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mc_pricer

    cat << 'EOF' > /home/user/mc_pricer/data.csv
100000000.1
100000000.2
100000000.15
100000000.25
100000000.1
100000000.2
EOF

    cat << 'EOF' > /home/user/mc_pricer/Makefile
all:
	g++ -O3 pricer.cpp -o mc_pricer
clean:
	rm -f mc_pricer
EOF

    cat << 'EOF' > /home/user/mc_pricer/pricer.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <thread>
#include <fstream>
#include <cassert>
#include <string>

void compute_stats(const std::vector<double>& data, double& out_mean, double& out_stddev) {
    double sum = 0.0;
    double sum_sq = 0.0;

    for(double x : data) {
        sum += x;
        sum_sq += x * x;
    }

    double mean = sum / data.size();
    double var = (sum_sq / data.size()) - (mean * mean);

    out_stddev = std::sqrt(var);
    out_mean = mean;
}

void process_file(const std::string& filepath) {
    std::ifstream file(filepath);
    if (!file.is_open()) {
        std::cerr << "Failed to open file\n";
        return;
    }

    std::vector<double> data;
    double val;
    while (file >> val) {
        data.push_back(val);
    }

    double mean = 0.0;
    double stddev = 0.0;

    std::thread t(compute_stats, std::ref(data), std::ref(mean), std::ref(stddev));
    t.join();

    assert(!std::isnan(stddev) && "Standard deviation calculation resulted in NaN!");

    std::cout << stddev << std::endl;
}

int main() {
    process_file("data.csv");
    return 0;
}
EOF

    chmod -R 777 /home/user
