#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /home/user/seq_analyzer
mkdir -p /home/user/data
mkdir -p /home/user/expected
mkdir -p /home/user/results

cat << 'EOF' > /home/user/seq_analyzer/analyzer.cpp
#include <iostream>
#include <vector>
#include <string>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <random>

using namespace std;

// Convert DNA to signal: G/C = 1, A/T = 0
vector<double> dna_to_signal(const string& seq) {
    vector<double> sig(seq.length());
    for (size_t i = 0; i < seq.length(); i++) {
        sig[i] = (seq[i] == 'G' || seq[i] == 'C') ? 1.0 : 0.0;
    }
    return sig;
}

// Compute dominant period using naive DFT
int get_dominant_period(const vector<double>& signal) {
    int N = signal.size();
    vector<double> real(N, 0.0), imag(N, 0.0), mag(N, 0.0);

    int max_k = 1;
    double max_mag = -1.0;

    for (int k = 1; k < N/2; k++) { // Ignore DC component k=0
        for (int n = 0; n < N; n++) {
            double angle = 2.0 * M_PI * k * n / N;
            real[k] += signal[n] * cos(angle);
            imag[k] -= signal[n] * sin(angle);
        }
        mag[k] = sqrt(real[k]*real[k] + imag[k]*imag[k]);
        if (mag[k] > max_mag) {
            max_mag = mag[k];
            max_k = k;
        }
    }

    // BUG 1: Should return N / max_k, but currently returns max_k
    return max_k; 
}

// Log Likelihood for Binomial
double log_likelihood(double p, int gc_count, int N) {
    if (p <= 0 || p >= 1) return -1e9;
    return gc_count * log(p) + (N - gc_count) * log(1.0 - p);
}

// MCMC to estimate GC posterior mean
double estimate_gc_posterior(const string& seq) {
    int N = seq.length();
    int gc_count = 0;
    for (char c : seq) {
        if (c == 'G' || c == 'C') gc_count++;
    }

    mt19937 gen(42); // Fixed seed for reproducible tests
    normal_distribution<double> prop_dist(0.0, 0.05);
    uniform_real_distribution<double> unif(0.0, 1.0);

    double current_p = 0.5;
    double sum_p = 0.0;
    int iterations = 10000;
    int burn_in = 2000;

    for (int i = 0; i < iterations; i++) {
        double proposal_p = current_p + prop_dist(gen);

        double current_ll = log_likelihood(current_p, gc_count, N);
        double proposal_ll = log_likelihood(proposal_p, gc_count, N);

        // Acceptance ratio (log scale)
        // BUG 2: Inverted acceptance criteria. Should be proposal_ll - current_ll
        if (log(unif(gen)) < (current_ll - proposal_ll)) {
            current_p = proposal_p;
        }

        if (i >= burn_in) {
            sum_p += current_p;
        }
    }

    return sum_p / (iterations - burn_in);
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        cerr << "Usage: " << argv[0] << " <fasta_file>" << endl;
        return 1;
    }

    ifstream file(argv[1]);
    string line, seq_name, seq;

    while (getline(file, line)) {
        if (line.empty()) continue;
        if (line[0] == '>') {
            if (!seq.empty()) {
                vector<double> sig = dna_to_signal(seq);
                cout << "Sequence: " << seq_name << endl;
                cout << "Dominant Period: " << get_dominant_period(sig) << endl;
                cout << "GC Posterior Mean: " << fixed << setprecision(2) << estimate_gc_posterior(seq) << endl;
                cout << "---" << endl;
                seq.clear();
            }
            seq_name = line.substr(1);
        } else {
            seq += line;
        }
    }

    if (!seq.empty()) {
        vector<double> sig = dna_to_signal(seq);
        cout << "Sequence: " << seq_name << endl;
        cout << "Dominant Period: " << get_dominant_period(sig) << endl;
        cout << "GC Posterior Mean: " << fixed << setprecision(2) << estimate_gc_posterior(seq) << endl;
    }

    return 0;
}
EOF

cat << 'EOF' > /home/user/seq_analyzer/Makefile
CXX = g++
CXXFLAGS = -O2 -std=c++11 -Wall

all: seq_analyzer

seq_analyzer: analyzer.cpp
	$(CXX) $(CXXFLAGS) -o seq_analyzer analyzer.cpp

clean:
	rm -f seq_analyzer
EOF

cat << 'EOF' > /home/user/seq_analyzer/run_tests.sh
#!/bin/bash
cd /home/user/seq_analyzer
make > /dev/null 2>&1
./seq_analyzer /home/user/data/test.fasta > /tmp/test_out.log

diff -u /home/user/expected/test.out /tmp/test_out.log
if [ $? -eq 0 ]; then
    echo "Tests passed!"
    exit 0
else
    echo "Tests failed!"
    exit 1
fi
EOF
chmod +x /home/user/seq_analyzer/run_tests.sh

cat << 'EOF' > /home/user/data/test.fasta
>test_seq1
GCATGCATGCATGCATGCATGCAT
EOF

cat << 'EOF' > /home/user/expected/test.out
Sequence: test_seq1
Dominant Period: 4
GC Posterior Mean: 0.50
---
EOF

cat << 'EOF' > /home/user/data/reads.fasta
>read_A
CGCGATCGCGATCGCGATCGCGATCGCGAT
>read_B
ATATATATATATATATATATATATATATAT
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
