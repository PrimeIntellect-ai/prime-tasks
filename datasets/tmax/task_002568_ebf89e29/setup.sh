#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron procps binutils
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/incoming/
    mkdir -p /home/user/processed/

    # Create legacy filter source
    cat << 'EOF' > /tmp/legacy_filter.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unistd.h>

using namespace std;

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    ifstream in(argv[1]);
    ofstream out(argv[2]);
    string line;
    unordered_map<string, int> counts;

    if (getline(in, line)) {
        out << line << "\n";
    }

    while (getline(in, line)) {
        usleep(100);
        stringstream ss(line);
        string id, cat, v1_s, v2_s, v3_s;
        getline(ss, id, ',');
        getline(ss, cat, ',');
        getline(ss, v1_s, ',');
        getline(ss, v2_s, ',');
        getline(ss, v3_s, ',');

        try {
            double v1 = stod(v1_s);
            double v2 = stod(v2_s);
            double v3 = stod(v3_s);
            if (v1 * v1 + v2 * v2 <= v3) {
                if (counts[cat] < 5) {
                    out << line << "\n";
                    counts[cat]++;
                }
            }
        } catch (...) {}
    }
    return 0;
}
EOF

    mkdir -p /app
    g++ -O3 /tmp/legacy_filter.cpp -o /app/legacy_filter
    strip --strip-all /app/legacy_filter
    rm /tmp/legacy_filter.cpp

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
