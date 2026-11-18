#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential ffmpeg espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the primer audio file
    espeak -w /app/primer.wav "A C G T A A C C G G T T"

    # Create reads.fasta
    cat << 'EOF' > /app/reads.fasta
>seq1
ACGTACGTACGT
>seq2
CCGGTTCCGGTT
>seq3
ATGCATGCATGC
>seq4
TTTTCCCCGGGG
EOF

    # Create buggy analyze.cpp
    cat << 'EOF' > /app/analyze.cpp
#include <iostream>
#include <vector>
#include <string>
#include <cmath>
#include <fstream>
#include <omp.h>

using namespace std;

// Mock alignment score for simplicity in this example
double align_score(const string& a, const string& b) {
    double score = 0;
    for(size_t i=0; i<min(a.size(), b.size()); ++i) {
        if(a[i] == b[i]) score += 1.0;
    }
    return score;
}

int main(int argc, char** argv) {
    if(argc < 2) return 1;
    string primer = argv[1];
    vector<string> seqs = {primer, "ACGTACGTACGT", "CCGGTTCCGGTT", "ATGCATGCATGC", "TTTTCCCCGGGG"};

    int n = seqs.size();
    vector<vector<double>> M(n, vector<double>(n, 0));
    for(int i=0; i<n; ++i) {
        for(int j=0; j<n; ++j) {
            M[i][j] = align_score(seqs[i], seqs[j]);
        }
    }

    vector<double> v(n, 1.0);
    for(int iter=0; iter<50; ++iter) {
        vector<double> v_new(n, 0.0);
        #pragma omp parallel for
        for(int i=0; i<n; ++i) {
            for(int j=0; j<n; ++j) {
                v_new[i] += M[i][j] * v[j];
            }
        }

        double norm = 0;
        // BUG: race condition in reduction
        #pragma omp parallel for
        for(int i=0; i<n; ++i) {
            norm += v_new[i] * v_new[i]; 
        }
        norm = sqrt(norm);

        for(int i=0; i<n; ++i) {
            v[i] = v_new[i] / norm;
        }
    }

    double eigenvalue = 0;
    // BUG: race condition in reduction
    #pragma omp parallel for
    for(int i=0; i<n; ++i) {
        double row_sum = 0;
        for(int j=0; j<n; ++j) {
            row_sum += M[i][j] * v[j];
        }
        eigenvalue += v[i] * row_sum;
    }

    cout << eigenvalue << endl;
    return 0;
}
EOF

    # Create evaluation script
    cat << 'EOF' > /tmp/eval.py
import sys

try:
    with open('/home/user/eigenvalue.txt', 'r') as f:
        val = float(f.read().strip())
except:
    print("0") # Failed to read
    sys.exit(0)

expected = 25.10967
error = abs(val - expected)
if error < 1e-3:
    print("1")
else:
    print("0")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
