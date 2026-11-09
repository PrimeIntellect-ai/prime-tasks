#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>

int main() {
    long long sum = 0;
    long long val;
    while (std::cin >> val) {
        if (val >= 0 && val % 2 == 0) {
            sum += val * val;
        }
    }
    std::cout << sum << std::endl;
    return 0;
}
EOF
    g++ -O3 /tmp/oracle.cpp -o /app/oracle_processor
    strip /app/oracle_processor
    rm /tmp/oracle.cpp

    mkdir -p /home/user/workspace
    cat << 'EOF' > /home/user/workspace/Makefile
all:
	g++ -O3 processor.cpp -o processor_fixed
EOF

    cat << 'EOF' > /home/user/workspace/processor.cpp
#include <iostream>
#include <vector>
// Missing thread and mutex headers to trigger compiler errors

long long global_sum = 0;
// Missing mutex for global_sum

void process_chunk(const std::vector<int>& data, int start, int end) {
    for (int i = start; i < end; ++i) {
        if (data[i] >= 0 && data[i] % 2 == 0) {
            long long val = data[i];
            // Race condition here:
            global_sum += (val * val);
        }
    }
}

int main() {
    std::vector<int> data;
    int num;
    while (std::cin >> num) {
        data.push_back(num);
    }

    int num_threads = 4;
    std::vector<std::thread> threads;
    int chunk_size = data.size() / num_threads;

    for (int i = 0; i < num_threads; ++i) {
        int start = i * chunk_size;
        int end = (i == num_threads - 1) ? data.size() : start + chunk_size;
        threads.push_back(std::thread(process_chunk, std::ref(data), start, end));
    }

    for (auto& t : threads) {
        t.join();
    }

    std::cout << global_sum << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
