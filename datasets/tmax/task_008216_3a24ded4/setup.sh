#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tshark tcpdump g++
pip3 install pytest scapy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/newton_solver.cpp
#include <iostream>
#include <cmath>
#include <string>

#define MAX_ITER 50

double f(double x) { return x*x*x - x; }
double df(double x) { return 3*x*x - 1; }

int main(int argc, char** argv) {
    if(argc < 2) {
        std::cerr << "Missing argument" << std::endl;
        return 1;
    }

    double guess = std::stod(argv[1]);
    double history[MAX_ITER]; 
    double x = guess;
    int iter = 0;

    // BUG 1: iter <= MAX_ITER writes out of bounds on the 50th iteration
    // BUG 2: df(x) can be 0, leading to division by zero and NaN
    while (std::abs(f(x)) > 1e-6 && iter <= MAX_ITER) {
        history[iter] = x;
        double deriv = df(x);

        x = x - f(x) / deriv;
        iter++;
    }

    if (iter >= MAX_ITER || std::isnan(x)) {
        std::cout << "FAILED" << std::endl;
    } else {
        std::cout << "CONVERGED: " << x << std::endl;
    }
    return 0;
}
EOF

cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
pkts = [
    IP(dst="127.0.0.1")/UDP(dport=8080)/Raw(load=b"2.0"),
    IP(dst="127.0.0.1")/UDP(dport=8080)/Raw(load=b"0.577350269"),
    IP(dst="127.0.0.1")/UDP(dport=8080)/Raw(load=b"-0.5"),
    IP(dst="127.0.0.1")/UDP(dport=8080)/Raw(load=b"1.0")
]
wrpcap('/home/user/traffic.pcap', pkts)
EOF

python3 /tmp/gen_pcap.py

chmod -R 777 /home/user
