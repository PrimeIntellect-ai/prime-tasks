#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/calc.cpp
#include <iostream>
#include <string>
#include <cstdlib>

using namespace std;

long long SEQ(long long x, long long y) {
    if (x == 0) return y + 2;
    if (y == 0) return SEQ(x - 1, 1);
    return SEQ(x - 1, SEQ(x, y - 1)) + x * y;
}

int main() {
    string input;
    if (!(cin >> input)) return 0;

    // Deliberate memory leak
    char* leak = (char*)malloc(1024);
    (void)leak;

    if (input.substr(0, 4) != "SEQ[") {
        int* p = nullptr;
        *p = 1;
    }
    size_t comma = input.find(',');
    size_t bracket = input.find(']');
    if (comma == string::npos || bracket == string::npos) {
        int* p = nullptr;
        *p = 1;
    }
    long long x = stoll(input.substr(4, comma - 4));
    long long y = stoll(input.substr(comma + 1, bracket - comma - 1));
    if (x < 0 || y < 0) {
        int* p = nullptr;
        *p = 1;
    }

    cout << SEQ(x, y) << endl;
    return 0;
}
EOF

    g++ -O2 /app/calc.cpp -o /app/calc_service_stripped
    strip /app/calc_service_stripped
    rm /app/calc.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
