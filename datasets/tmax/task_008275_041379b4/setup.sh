#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    # Generate the system.log file
    cat << 'EOF' > /home/user/generate_log.py
import os

with open('/home/user/system.log', 'w') as f:
    for i in range(1000):
        # Timestamp
        ts = 1600000000 + i
        # Hex encoded payload (alternating cases to trigger bug)
        base_str = f"payload_data_{i}".encode('utf-8').hex()
        if i % 2 == 0:
            hex_str = base_str.upper()
        else:
            hex_str = base_str.lower()
        # Response time (cluster to trigger naive variance cancellation)
        # e.g., 10000.000 + 0.001 * (i % 10)
        resp = 10000.0 + (i % 10) * 0.001
        f.write(f"{ts} {hex_str} {resp:.4f}\n")
EOF
    python3 /home/user/generate_log.py
    rm /home/user/generate_log.py

    # Create the log_analyzer.cpp file
    cat << 'EOF' > /home/user/log_analyzer.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <iomanip>
#include <cmath>

using namespace std;

// BUG 1: Encoding issue - only handles lowercase a-f
int hexCharToInt(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    // Missing A-F handling
    return -1; 
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <input_log> <output_json>\n";
        return 1;
    }

    ifstream infile(argv[1]);
    if (!infile.is_open()) return 1;

    string line;
    vector<string> lines;
    while (getline(infile, line)) {
        lines.push_back(line);
    }

    int total_entries = 0;
    long long decoded_bytes_count = 0;

    double sum_x = 0.0;
    double sum_x2 = 0.0;

    // BUG 2: Boundary condition - skips the last line (i < lines.size() - 1)
    for (size_t i = 0; i < lines.size() - 1; ++i) {
        const string& l = lines[i];
        if (l.empty()) continue;

        size_t space1 = l.find(' ');
        size_t space2 = l.find(' ', space1 + 1);

        if (space1 == string::npos || space2 == string::npos) continue;

        string ts_str = l.substr(0, space1);
        string hex_str = l.substr(space1 + 1, space2 - space1 - 1);
        string resp_str = l.substr(space2 + 1);

        // Hex decoding
        for (size_t j = 0; j < hex_str.length(); j += 2) {
            int h1 = hexCharToInt(hex_str[j]);
            int h2 = hexCharToInt(hex_str[j+1]);
            if (h1 != -1 && h2 != -1) {
                decoded_bytes_count++;
            }
        }

        // Variance calculation metrics
        double val = stod(resp_str);
        sum_x += val;
        sum_x2 += (val * val);

        total_entries++;
    }

    // BUG 3: Numerical instability - naive variance formula
    // With values clustered around 10000, sum_x2 and (sum_x*sum_x/n) are huge
    // Catastrophic cancellation occurs here.
    double mean = sum_x / total_entries;
    double variance = (sum_x2 - (sum_x * sum_x) / total_entries) / total_entries;

    ofstream outfile(argv[2]);
    outfile << "{\n";
    outfile << "  \"total_entries\": " << total_entries << ",\n";
    outfile << "  \"decoded_bytes_count\": " << decoded_bytes_count << ",\n";
    outfile << "  \"variance\": " << fixed << setprecision(10) << variance << "\n";
    outfile << "}\n";

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
