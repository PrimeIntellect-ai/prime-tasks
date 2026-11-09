#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest

    mkdir -p /home/user/risk_engine
    cd /home/user/risk_engine
    git init

    cat << 'EOF' > calc.cpp
#include <iostream>
#include <vector>
#include <cstdlib>
#include <stdexcept>

using namespace std;

int main(int argc, char** argv) {
    if (argc != 2) {
        cerr << "Usage: calc <portfolio_id>" << endl;
        return 1;
    }
    int portfolio_id = atoi(argv[1]);

    // Simulated asset prices for the given portfolio
    vector<double> prices = {10.5, 12.0, 11.5, 15.0, 14.5};
    if (portfolio_id == 9942) {
        // This price triggers the bug
        prices.push_back(20.0); 
    }

    double min_p = 10.0;
    double max_p = 20.0;
    int num_buckets = 5;
    double bucket_size = (max_p - min_p) / num_buckets;

    vector<int> histogram(num_buckets, 0);

    for (double p : prices) {
        // ALGORITHMIC BUG: if p == max_p, bucket == num_buckets (out of bounds)
        int bucket = (p - min_p) / bucket_size;

        if (bucket < 0) bucket = 0;
        // Missing constraint: if (bucket >= num_buckets) bucket = num_buckets - 1;

        // .at() will throw std::out_of_range and crash the program for index 5
        histogram.at(bucket) += 1; 
    }

    int score = 0;
    for(int i = 0; i < num_buckets; ++i) {
        score += histogram[i] * (i + 1);
    }

    cout << "Risk Score: " << score << endl;
    return 0;
}
EOF

    git config user.name "Departing Dev"
    git config user.email "dev@company.com"
    git add calc.cpp
    git commit -m "Initial commit of risk calculator"

    # Delete the file to simulate the accident
    rm calc.cpp
    git add calc.cpp
    git commit -m "cleanup old files"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/risk_engine
    chmod -R 777 /home/user
