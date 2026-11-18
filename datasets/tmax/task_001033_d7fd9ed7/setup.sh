#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <cctype>
#include <algorithm>

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        std::string result = "";
        bool in_dash = false;

        for (char c : line) {
            if (std::isalnum(static_cast<unsigned char>(c))) {
                result += std::tolower(static_cast<unsigned char>(c));
                in_dash = false;
            } else {
                if (!in_dash) {
                    result += '-';
                    in_dash = true;
                }
            }
        }

        // Trim leading dash
        if (!result.empty() && result.front() == '-') {
            result.erase(0, 1);
        }
        // Trim trailing dash
        if (!result.empty() && result.back() == '-') {
            result.pop_back();
        }

        std::cout << "artifact-" << result << ".bin\n";
    }
    return 0;
}
EOF

    g++ -O3 /tmp/oracle.cpp -o /app/legacy_indexer
    strip /app/legacy_indexer
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
