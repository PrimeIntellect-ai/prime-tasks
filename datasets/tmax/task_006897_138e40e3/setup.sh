#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/evaluate.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>

struct Record {
    std::string text;
    int label;
};

// Computes the ratio of vowels to total string length
double compute_feature(const std::string& text) {
    if (text.empty()) return 0.0;
    // TODO: Implement vowel counting logic
    // Bug 1: Missing implementation
    return 0.0; 
}

int main() {
    std::vector<Record> data = {
        {"hello world", 1},
        {"xyz", 0},
        {"aeiou", 1},
        {"bcdfg", 0},
        {"beautiful day", 1},
        {"hmmm", 0}
    };

    double best_acc = -1.0;
    double best_thresh = 0.0;

    for (double thresh = 0.0; thresh <= 1.0; thresh += 0.1) {
        int correct = 0;
        for (size_t i = 0; i < data.size(); ++i) {
            double feature = compute_feature(data[i].text);
            int pred = (feature >= thresh) ? 1 : 0;
            if (pred == data[i].label) correct++;
        }
        double acc = (double)correct / data.size();
        if (acc > best_acc) {
            best_acc = acc;
            best_thresh = thresh;
        }
    }

    // Bug 2: Opening ofstream with std::ios::in prevents writing
    std::ofstream out("report.txt", std::ios::in);
    if (out.is_open()) {
        out << "Best Threshold: " << best_thresh << "\n";
        out << "Accuracy: " << best_acc << "\n";
        out.close();
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
