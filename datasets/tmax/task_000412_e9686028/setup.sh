#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <map>
#include <vector>
#include <sstream>
#include <algorithm>

using namespace std;

int main() {
    string line;
    string prev_line = "";
    // map<bucket, map<locale, score>>
    map<long long, map<string, long long>> aggregates;

    while (getline(cin, line)) {
        if (line.empty()) continue;
        if (line == prev_line) continue;
        prev_line = line;

        stringstream ss(line);
        string ts_str, locale, event, wc_str;
        getline(ss, ts_str, ',');
        getline(ss, locale, ',');
        getline(ss, event, ',');
        getline(ss, wc_str, ',');

        long long ts = stoll(ts_str);
        long long wc = stoll(wc_str);
        long long bucket = (ts / 3600) * 3600;

        long long multiplier = 0;
        if (event == "translated") multiplier = 1;
        else if (event == "reviewed") multiplier = 2;

        if (multiplier > 0) {
            aggregates[bucket][locale] += (wc * multiplier);
        }
    }

    for (auto const& [bucket, loc_map] : aggregates) {
        for (auto const& [loc, score] : loc_map) {
            if (score > 0) {
                cout << bucket << "," << loc << "," << score << "\n";
            }
        }
    }
    return 0;
}
EOF
    g++ -O3 -o /app/oracle /tmp/oracle.cpp
    rm /tmp/oracle.cpp
    chmod +x /app/oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
