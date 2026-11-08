#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sequence.fasta
>sequence_1
ACGTACGTACGTACGTACGTACGTACGTACGT
ACGTACGTACGTACGTACGTACGTACGTACGT
EOF

    cat << 'EOF' > /home/user/spectral_analysis.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <iomanip>

int main() {
    std::ifstream file("/home/user/sequence.fasta");
    std::string line, seq = "";
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '>') continue;
        seq += line;
    }

    std::vector<float> signal;
    for (char c : seq) {
        if (c == 'A') signal.push_back(1.0f);
        else if (c == 'C') signal.push_back(2.0f);
        else if (c == 'G') signal.push_back(-1.0f);
        else if (c == 'T') signal.push_back(-2.0f);
    }

    int N = signal.size();
    float total_magnitude = 0.0f;

    for (int k = 0; k < N; ++k) {
        float re = 0.0f;
        float im = 0.0f;
        for (int n = 0; n < N; ++n) {
            float angle = -2.0f * M_PI * k * n / N;
            re += signal[n] * cos(angle);
            im += signal[n] * sin(angle);
        }
        float mag = sqrt(re*re + im*im);
        total_magnitude += mag;
    }

    std::cout << std::fixed << std::setprecision(6) << total_magnitude << std::endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
