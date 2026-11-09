#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/math_worker.cpp
#include <iostream>
#include <vector>
#include <string>
#include <thread>

int collatz(long long n) {
    int steps = 0;
    while (n > 1) {
        if (n % 2 == 0) n /= 2;
        else n = 3 * n + 1;
        steps++;
    }
    return steps;
}

void process_chunk(const std::vector<long long>& data, int start, int end) {
    for (int i = start; i < end; ++i) {
        if (data[i] <= 0) {
            std::cout << "Number: " << data[i] << ", Error: Domain" << "\n";
            continue;
        }
        int steps = collatz(data[i]);
        // Intentional race condition on std::cout
        std::cout << "Number: " << data[i] << ", Steps: " << steps << "\n";
    }
}

int main(int argc, char* argv[]) {
    std::vector<long long> data;
    for (int i = 1; i < argc; ++i) {
        data.push_back(std::stoll(argv[i]));
    }

    int num_threads = 4;
    std::vector<std::thread> threads;
    int chunk_size = data.size() / num_threads;

    for (int i = 0; i < num_threads; ++i) {
        int start = i * chunk_size;
        int end = (i == num_threads - 1) ? data.size() : (i + 1) * chunk_size;
        threads.emplace_back(process_chunk, std::cref(data), start, end);
    }

    for (auto& t : threads) {
        t.join();
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/parser.py
import sys
import subprocess
import re

def process_data(file_path):
    with open(file_path, 'r') as f:
        data = [line.strip() for line in f if line.strip()]

    # Run the C++ worker
    cmd = ["/home/user/math_worker"] + data
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT, universal_newlines=True)
    except subprocess.CalledProcessError as e:
        print("Worker failed:", e.output)
        sys.exit(1)

    results = {}
    for line in result.split('\n'):
        if not line:
            continue

        match = re.match(r"Number: (-?\d+), Steps: (\d+)", line)
        if match:
            results[int(match.group(1))] = int(match.group(2))
        else:
            raise ValueError(f"Format parsing error on line: '{line}'")

    print(f"Successfully parsed {len(results)} records.")

if __name__ == "__main__":
    process_data(sys.argv[1])
EOF

    python3 -c "
import random
random.seed(42)
with open('/home/user/data_batch.txt', 'w') as f:
    for i in range(10000):
        if i == 7382:
            f.write('-14\n') # The deterministic edge case
        else:
            f.write(str(random.randint(1, 1000000)) + '\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
