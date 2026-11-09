#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget unzip build-essential g++
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget -qO libb64.zip https://downloads.sourceforge.net/project/libb64/libb64/libb64/libb64-1.2.1.zip
    unzip libb64.zip
    rm libb64.zip

    # Build libb64 to link with oracle
    cd /app/libb64-1.2.1
    make

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <string>
#include <vector>

extern "C" {
#include "b64/cdecode.h"
}

using namespace std;

int main() {
    string input;
    char c;
    while (cin.get(c)) {
        input += c;
    }

    string tag_start = "[B64]";
    string tag_end = "[/B64]";

    size_t pos = 0;
    while (pos < input.length()) {
        size_t start_idx = input.find(tag_start, pos);
        if (start_idx == string::npos) {
            cout << input.substr(pos);
            break;
        }

        cout << input.substr(pos, start_idx - pos);
        size_t end_idx = input.find(tag_end, start_idx + tag_start.length());
        if (end_idx == string::npos) {
            cout << input.substr(start_idx);
            break;
        }

        string b64_str = input.substr(start_idx + tag_start.length(), end_idx - (start_idx + tag_start.length()));

        base64_decodestate state;
        base64_init_decodestate(&state);
        vector<char> out(b64_str.length() + 1);
        int decoded_len = base64_decode_block(b64_str.c_str(), b64_str.length(), out.data(), &state);
        cout.write(out.data(), decoded_len);

        pos = end_idx + tag_end.length();
    }
    return 0;
}
EOF

    g++ -O3 -I/app/libb64-1.2.1/include /opt/oracle/oracle.cpp -L/app/libb64-1.2.1/src -lb64 -o /opt/oracle/doc_extractor_oracle

    # Clean libb64 so the agent has to build it
    cd /app/libb64-1.2.1
    make clean

    # Perturb the Makefile
    cd /app/libb64-1.2.1/src
    sed -i 's/cencode\.c/cencd.c/g' Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
