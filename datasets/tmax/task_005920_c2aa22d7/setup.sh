#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk
    pip3 install pytest

    mkdir -p /home/user/ticket_8831

    cat << 'EOF' > /home/user/ticket_8831/processor.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cassert>
#include <iomanip>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename>\n";
        return 1;
    }

    std::ifstream fin(argv[1]);
    if (!fin) {
        std::cerr << "Error opening file\n";
        return 1;
    }

    std::vector<float> values; // BUG: precision loss
    float val;
    while (fin >> val) {
        values.push_back(val);
    }

    float sum = 0.0f; // BUG: precision loss
    int n = values.size();

    // BUG: Off-by-one error (skips index 0, reads index n)
    for(int i = 1; i <= n; i++) {
        sum += values[i];
    }

    std::cout << std::fixed << std::setprecision(6) << sum << std::endl;
    return 0;
}
EOF

    awk 'BEGIN { for(i=0; i<100000; i++) print "1000.01" }' > /home/user/ticket_8831/data.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/ticket_8831
    chmod -R 777 /home/user
