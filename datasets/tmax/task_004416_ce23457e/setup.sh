#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Create oracle C++ program
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <unordered_set>

using namespace std;

int main() {
    string line;
    unordered_set<string> seen;
    while (getline(cin, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string item;
        vector<string> cols;
        while (getline(ss, item, ',')) {
            cols.push_back(item);
        }
        if (cols.size() != 4) {
            cerr << "WARNING: Invalid line\n";
            continue;
        }
        try {
            size_t pos;
            stoi(cols[0], &pos);
            if (pos != cols[0].length()) {
                cerr << "WARNING: Invalid line\n";
                continue;
            }
        } catch (...) {
            cerr << "WARNING: Invalid line\n";
            continue;
        }

        if (seen.find(line) != seen.end()) {
            continue;
        }
        seen.insert(line);

        cout << cols[0] << ",SensorAlpha," << cols[1] << "\n";
        cout << cols[0] << ",SensorBeta," << cols[2] << "\n";
        cout << cols[0] << ",SensorGamma," << cols[3] << "\n";
    }
    return 0;
}
EOF

    g++ -O3 -o /app/oracle_process_telemetry /app/oracle.cpp
    rm /app/oracle.cpp

    # Generate audio
    espeak -w /app/telemetry_log.wav "Timestamp 1620000000. Sensor Alpha 45 point 2. Sensor Beta 12 point 0. Sensor Gamma 9 point 1. Timestamp 1620000000. Sensor Alpha 45 point 2. Sensor Beta 12 point 0. Sensor Gamma 9 point 1. Timestamp 1620000010. Sensor Alpha 46 point 1. Sensor Beta 11 point 8. Sensor Gamma 9 point 5."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
