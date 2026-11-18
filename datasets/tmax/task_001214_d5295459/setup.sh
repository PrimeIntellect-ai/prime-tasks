#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/source.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <cmath>
#include <iomanip>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    ifstream infile(argv[1]);
    string line;

    double ewma = 0.0;
    double sse = 0.0;
    int valid_lines = 0;

    while (getline(infile, line)) {
        stringstream ss(line);
        string token;
        vector<string> tokens;
        while (ss >> token) {
            tokens.push_back(token);
        }
        if (tokens.size() != 7) continue;

        string ts = tokens[0];
        if (ts.size() < 2 || ts.front() != '[' || ts.back() != ']') continue;
        ts = ts.substr(1, ts.size() - 2);

        double size;
        try {
            size = stod(tokens[6]);
        } catch (...) {
            continue;
        }

        cout << ts << "\t" << tokens[1] << "\t" << tokens[2] << "\t" << tokens[3] << "\t" << tokens[5] << "\t" << tokens[6] << "\n";

        if (valid_lines == 0) {
            ewma = size;
        } else {
            ewma = 0.3 * size + 0.7 * ewma;
            sse += (size - ewma) * (size - ewma);
        }
        valid_lines++;
    }

    if (valid_lines > 0) {
        double score = sqrt(sse / valid_lines);
        cout << "ANOMALY_SCORE: " << fixed << setprecision(4) << score << "\n";
    } else {
        cout << "ANOMALY_SCORE: 0.0000\n";
    }

    return 0;
}
EOF

    g++ -O3 /app/source.cpp -o /app/log_anomaly_detector
    strip /app/log_anomaly_detector
    chmod +x /app/log_anomaly_detector
    rm /app/source.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
