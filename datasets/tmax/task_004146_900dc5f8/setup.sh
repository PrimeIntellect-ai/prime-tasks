#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/train_model.cpp
#include <iostream>
#include <string>
#include <iomanip>

struct ExperimentMetrics {
    int final_loss; // BUG: Should be double
};

void train_model(double lr) {
    double initial_loss = 100.0;
    double current_loss = initial_loss;

    // Simulate 100 epochs of training
    for(int i = 1; i <= 100; ++i) {
        current_loss = 100.0 / (1.0 + lr * 100.5);
    }

    ExperimentMetrics metrics;
    metrics.final_loss = current_loss; // Silent truncation happens here

    std::cout << "Training complete." << std::endl;
    std::cout << "FINAL_LOSS=" << std::fixed << std::setprecision(4) << (double)metrics.final_loss << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <learning_rate>" << std::endl;
        return 1;
    }

    double lr = std::stod(argv[1]);
    train_model(lr);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
