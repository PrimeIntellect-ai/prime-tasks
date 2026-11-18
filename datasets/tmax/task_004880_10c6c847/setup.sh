#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/primer_sim.cpp
#include <iostream>
#include <string>
#include <vector>
#include <random>
#include <fstream>

const std::string TARGET = "GCTAGCTAGCTAGCTAGCTA"; 
std::mt19937 gen(42);

double score_primer(const std::string& primer) {
    if (primer.length() != 10) return 0.0;
    double total_score = 0.0;
    std::uniform_real_distribution<> dis(0.0, 1.0);

    for (int mc = 0; mc < 100; ++mc) {
        std::string noisy_target = TARGET;
        for (char& c : noisy_target) {
            if (dis(gen) < 0.1) {
                const char bases[] = {'A', 'C', 'G', 'T'};
                c = bases[gen() % 4];
            }
        }

        int best_match = 0;
        for (size_t i = 0; i <= noisy_target.length() - 10; ++i) {
            int matches = 0;
            for (size_t j = 0; j < 10; ++j) {
                if (primer[j] == noisy_target[i+j]) matches++;
            }
            if (matches > best_match) best_match = matches;
        }
        total_score += best_match;
    }
    return total_score / 100.0;
}

std::string find_best_primer() {
    // YOUR CODE HERE
    return "AAAAAAAAAA";
}

int main() {
    std::string best = find_best_primer();
    double score = score_primer(best);
    std::ofstream out("/home/user/best_primer.txt");
    out << "Primer: " << best << "\nScore: " << score << "\n";
    return 0;
}
EOF

    chmod -R 777 /home/user
