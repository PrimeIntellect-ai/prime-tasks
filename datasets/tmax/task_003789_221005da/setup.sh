#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak-ng build-essential
pip3 install pytest scipy numpy

mkdir -p /app
espeak-ng -w /app/voicemail.wav "The mean is zero point five. The standard deviation is zero point one five."

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/naive_w1.cpp
#include <iostream>
#include <vector>
#include <random>
#include <cmath>
#include <iomanip>

double normal_cdf(double x, double mean, double stddev) {
    return 0.5 * (1.0 + std::erf((x - mean) / (stddev * std::sqrt(2.0))));
}

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <N_samples> <mean> <stddev>\n";
        return 1;
    }
    int N = std::stoi(argv[1]);
    double mean = std::stod(argv[2]);
    double stddev = std::stod(argv[3]);

    std::mt19937 gen(42);
    std::uniform_real_distribution<double> dist(0.0, 1.0);
    std::vector<double> samples(N);
    for (int i = 0; i < N; ++i) {
        samples[i] = dist(gen);
    }

    int M = 1000000;
    double w1 = 0.0;
    double dx = 1.0 / M;

    for (int j = 1; j <= M; ++j) {
        double x = j * dx;

        int count = 0;
        for (int i = 0; i < N; ++i) {
            if (samples[i] <= x) count++;
        }
        double ecdf = (double)count / N;
        double ncdf = normal_cdf(x, mean, stddev);

        w1 += std::abs(ecdf - ncdf) * dx;
    }

    std::cout << std::fixed << std::setprecision(6) << w1 << std::endl;
    return 0;
}
EOF

chmod -R 777 /home/user
