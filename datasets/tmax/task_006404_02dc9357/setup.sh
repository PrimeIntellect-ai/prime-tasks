#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y g++ binutils

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the source code file
    cat << 'EOF' > /home/user/align_calc.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <string>

using namespace std;

// Simulate sequence alignment and primer distribution extraction
void calculate_kmer_distribution(vector<double>& dist) {
    for (int i = 0; i < 1000; ++i) {
        dist.push_back(abs(sin(i)));
    }
}

// Probability distribution distance metric
void compute_kl_divergence(const vector<double>& p, const vector<double>& q) {
    double kl = 0.0;
    for (size_t i = 0; i < p.size(); ++i) {
        if (p[i] > 0 && q[i] > 0) {
            kl += p[i] * log(p[i] / q[i]);
        }
    }
}

// Deliberately slow numerical integration of the probability density function
double numerical_integration_pdf() {
    double area = 0.0;
    double a = 0.0;
    double b = 100.0;
    int n = 50000000; // Large number of steps to simulate bottleneck
    double dx = (b - a) / n;

    for (int i = 0; i < n; ++i) {
        double x = a + i * dx;
        area += std::exp(-x * x / 2.0) * dx; // standard normal PDF approximation integration
    }
    return area;
}

// Statistical hypothesis comparison
bool hypothesis_test(double test_statistic) {
    double p_value = 0.05;
    return test_statistic > p_value;
}

int main() {
    vector<double> p, q;
    calculate_kmer_distribution(p);
    calculate_kmer_distribution(q);

    // Slight variation for q
    for (auto& val : q) val += 0.01;

    compute_kl_divergence(p, q);

    double integral = numerical_integration_pdf();
    hypothesis_test(integral);

    return 0;
}
EOF

    # Set permissions
    chmod -R 777 /home/user
