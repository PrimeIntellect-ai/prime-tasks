#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb valgrind ffmpeg espeak
    pip3 install pytest

    mkdir -p /app/bin
    mkdir -p /home/user

    # Create oracle C++ code
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <cctype>

using namespace std;

int main() {
    long long acc = 0;
    string cmd;
    while (cin >> cmd) {
        if (cmd == "ADD") {
            long long val; if (cin >> val) acc += val;
        } else if (cmd == "SUB") {
            long long val; if (cin >> val) acc -= val;
        } else if (cmd == "MUL") {
            long long val; if (cin >> val) acc *= val;
        } else if (cmd == "HEX") {
            string hex_str;
            if (cin >> hex_str) {
                bool valid = true;
                if (hex_str.length() != 2) valid = false;
                else {
                    for(char c : hex_str) {
                        if (!isxdigit(c)) valid = false;
                    }
                }
                if (valid) {
                    acc += stoi(hex_str, nullptr, 16);
                }
            }
        } else if (cmd == "REV") {
            acc = -acc;
        } else if (cmd == "END") {
            break;
        }
    }
    cout << acc << endl;
    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/bin/oracle_parser
    rm /app/oracle.cpp

    # Create buggy C++ code
    cat << 'EOF' > /home/user/fast_parser.cpp
#include <iostream>
#include <string>
#include <cctype>

using namespace std;

int main() {
    long long acc = 0;
    string cmd;
    while (cin >> cmd) {
        if (cmd == "ADD") {
            long long val; if (cin >> val) acc += val;
        } else if (cmd == "SUB") {
            long long val; if (cin >> val) acc -= val;
        } else if (cmd == "MUL") {
            long long val; if (cin >> val) acc *= val;
        } else if (cmd == "HEX") {
            string hex_str;
            if (cin >> hex_str) {
                // Buggy manual parsing: assumes exact 2 chars and valid hex
                int val = 0;
                char c1 = toupper(hex_str[0]);
                char c2 = toupper(hex_str[1]);
                val += (c1 >= 'A' ? c1 - 'A' + 10 : c1 - '0') * 16;
                val += (c2 >= 'A' ? c2 - 'A' + 10 : c2 - '0');
                acc += val;
            }
        } else if (cmd == "REV") {
            acc = -acc;
        } else if (cmd == "END") {
            break;
        }
    }
    cout << acc << endl;
    return 0;
}
EOF

    # Generate issue report audio
    espeak -w /app/issue_report.wav "Regression test sequence is ADD fifteen HEX one G MUL four END"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
