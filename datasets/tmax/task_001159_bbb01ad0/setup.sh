#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.cpp
#include <iostream>
#include <string>
#include <unordered_set>
#include <cctype>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    string line;
    unordered_set<string> seen;
    while (getline(cin, line)) {
        string normalized = "";
        bool in_space = true;
        for (char c : line) {
            if (isalnum((unsigned char)c)) {
                normalized += tolower((unsigned char)c);
                in_space = false;
            } else {
                if (!in_space) {
                    normalized += ' ';
                    in_space = true;
                }
            }
        }
        if (!normalized.empty() && normalized.back() == ' ') {
            normalized.pop_back();
        }
        if (!normalized.empty()) {
            if (seen.find(normalized) == seen.end()) {
                seen.insert(normalized);
                cout << normalized << "\n";
            }
        }
    }
    return 0;
}
EOF

    g++ -O3 /tmp/legacy.cpp -o /app/legacy_dedup
    strip /app/legacy_dedup
    rm /tmp/legacy.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
