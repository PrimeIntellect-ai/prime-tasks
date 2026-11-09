#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/concurrent_processor.cpp
#include <iostream>
#include <vector>
#include <thread>
#include <string>

int total_sum = 0; // The bug: not thread-safe

void process_chunk(const std::vector<int>& data, int start, int end) {
    for (int i = start; i < end; ++i) {
        total_sum += data[i]; // Data race occurs here
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <N>\n";
        return 1;
    }

    int num_elements = std::stoi(argv[1]);
    std::vector<int> data(num_elements, 1);

    int num_threads = 4;
    std::vector<std::thread> threads;
    int chunk_size = num_elements / num_threads;

    for (int i = 0; i < num_threads; ++i) {
        int start = i * chunk_size;
        int end = (i == num_threads - 1) ? num_elements : start + chunk_size;
        threads.emplace_back(process_chunk, std::cref(data), start, end);
    }

    for (auto& t : threads) {
        t.join();
    }

    std::cout << total_sum << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
