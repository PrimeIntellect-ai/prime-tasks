#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,value
1,10.5
2,12.0
3,15.2
4,18.1
5,14.3
6,19.5
EOF

    cat << 'EOF' > /home/user/libmathops.c
double compute_mean(double* data, int n) {
    double sum = 0;
    for(int i=0; i<n; i++) sum += data[i];
    return sum / n;
}
EOF

    cat << 'EOF' > /home/user/processor.cpp
#include <iostream>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <iomanip>

// TODO: Fix the ABI linkage issue
double compute_mean(double* data, int n);

int main() {
    // TODO: Implement parsing of /home/user/data.csv
    // TODO: Compute moving average of window size 3
    // TODO: Sort descending
    // TODO: Write to /home/user/output.txt with 2 decimal places
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
