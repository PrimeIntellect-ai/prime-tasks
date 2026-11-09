#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data_gen.cpp
#include <iostream>
#include <vector>
#include <thread>
#include <mutex>
#include <cmath>
#include <iomanip>
#include <fstream>

const int N = 1000;
const int NUM_THREADS = 10;
std::mutex mtx;
double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;

void process_block(int thread_id) {
    int rows_per_thread = N / NUM_THREADS;
    int start_row = thread_id * rows_per_thread;
    int end_row = start_row + rows_per_thread;

    double loc_x = 0, loc_y = 0, loc_xy = 0, loc_xx = 0;
    for(int i = start_row; i < end_row; ++i) {
        for(int j = 0; j < N; ++j) {
            double x = i * N + j;
            double y = std::sin(x * 0.001) + x * 0.005;
            loc_x += x;
            loc_y += y;
            loc_xy += x * y;
            loc_xx += x * x;
        }
    }

    std::lock_guard<std::mutex> lock(mtx);
    sum_x += loc_x;
    sum_y += loc_y;
    sum_xy += loc_xy;
    sum_xx += loc_xx;
}

int main() {
    std::vector<std::thread> threads;
    for(int i = 0; i < NUM_THREADS; ++i) {
        threads.push_back(std::thread(process_block, i));
    }
    for(auto& t : threads) {
        t.join();
    }

    double n_total = N * N;
    double slope = (n_total * sum_xy - sum_x * sum_y) / (n_total * sum_xx - sum_x * sum_x);
    double intercept = (sum_y - slope * sum_x) / n_total;

    std::ofstream out("/home/user/regression_result.txt");
    out << std::fixed << std::setprecision(9) << slope << "," << intercept << std::endl;
    return 0;
}
EOF

    chown user:user /home/user/data_gen.cpp
    chmod -R 777 /home/user
