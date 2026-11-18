#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/processor.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cmath>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    ifstream f(argv[1]);
    string line;
    double sum = 0;
    double sq_sum = 0;
    int count = 0;

    while (getline(f, line)) {
        size_t comma = line.find(',');
        if (comma == string::npos) continue;
        string val_str = line.substr(comma + 1);

        double val = stod(val_str); // Vulnerable to empty/invalid strings

        sum += val;
        sq_sum += val * val;
        count++;
    }

    if (count == 0) return 0;

    // Vulnerable to catastrophic cancellation
    double variance = (sq_sum - (sum * sum) / count) / count;
    double stddev = sqrt(variance);

    cout << argv[1] << "," << stddev << "\n";
    return 0;
}
EOF

    python3 -c "
import os
import random

data_dir = '/home/user/data/'
os.makedirs(data_dir, exist_ok=True)

for i in range(1000):
    with open(os.path.join(data_dir, f'data_{i}.txt'), 'w') as f:
        if i == 402:
            # Format parsing edge case: missing value
            f.write('1620000000,1.5\n')
            f.write('1620000001,\n') # This crashes stod
            f.write('1620000002,1.7\n')
        elif i == 783:
            # Numerical instability case: large values, tiny variance
            # Will cause catastrophic cancellation in naive formula
            f.write('1620000000,100000000.1\n')
            f.write('1620000001,100000000.2\n')
            f.write('1620000002,100000000.1\n')
            f.write('1620000003,100000000.3\n')
            f.write('1620000004,100000000.2\n')
        else:
            # Normal data
            f.write(f'1620000000,{random.uniform(10.0, 20.0)}\n')
            f.write(f'1620000001,{random.uniform(10.0, 20.0)}\n')
            f.write(f'1620000002,{random.uniform(10.0, 20.0)}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
