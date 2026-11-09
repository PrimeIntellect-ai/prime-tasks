#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user/sequence_project/src
    mkdir -p /home/user/sequence_project/bin
    mkdir -p /home/user/sequence_project/data

    cat << 'EOF' > /home/user/sequence_project/src/analyze_seqs.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <iomanip>

// Feature transformation offset to intentionally trigger catastrophic cancellation
// if a naive variance formula is used.
const double OFFSET = 1e8; 

double get_nucleotide_value(char c) {
    switch(c) {
        case 'A': return 10.0 + OFFSET;
        case 'C': return 20.0 + OFFSET;
        case 'G': return 30.0 + OFFSET;
        case 'T': return 40.0 + OFFSET;
        default: return 0.0 + OFFSET;
    }
}

// BUG: Naive variance calculation
double calculate_complexity_variance(const std::string& seq) {
    if (seq.empty()) return 0.0;

    double sum = 0.0;
    double sum_sq = 0.0;
    int count = 0;

    for (char c : seq) {
        if (c == '\n' || c == '\r') continue;
        double val = get_nucleotide_value(c);
        sum += val;
        sum_sq += (val * val);
        count++;
    }

    if (count == 0) return 0.0;

    double mean = sum / count;
    // Naive population variance formula
    double variance = (sum_sq / count) - (mean * mean);

    return variance;
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <fasta_file>\n";
        return 1;
    }

    std::ifstream file(argv[1]);
    if (!file.is_open()) {
        std::cerr << "Error opening file.\n";
        return 1;
    }

    std::string line, seq_id, seq_data;

    std::cout << std::fixed << std::setprecision(6);

    while (std::getline(file, line)) {
        if (line.empty()) continue;
        if (line[0] == '>') {
            if (!seq_id.empty()) {
                std::cout << seq_id << "," << calculate_complexity_variance(seq_data) << "\n";
            }
            seq_id = line.substr(1);
            seq_data = "";
        } else {
            seq_data += line;
        }
    }
    if (!seq_id.empty()) {
        std::cout << seq_id << "," << calculate_complexity_variance(seq_data) << "\n";
    }

    return 0;
}
EOF

    cat << 'EOF' > /tmp/generate_data.py
import random

def generate_fasta(filename, num_seqs, length, weights):
    with open(filename, 'w') as f:
        for i in range(num_seqs):
            seq = ''.join(random.choices(['A', 'C', 'G', 'T'], weights=weights, k=length))
            f.write(f">seq_{i}\n{seq}\n")

random.seed(42)
# Cohort A: slightly more uniform, different variance
generate_fasta('/home/user/sequence_project/data/cohort_A.fasta', 50, 1000, [0.25, 0.25, 0.25, 0.25])
# Cohort B: skewed, resulting in different variance
generate_fasta('/home/user/sequence_project/data/cohort_B.fasta', 50, 1000, [0.4, 0.1, 0.1, 0.4])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sequence_project
    chmod -R 777 /home/user
