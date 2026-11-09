#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        g++ \
        make \
        imagemagick \
        tesseract-ocr \
        libtesseract-dev \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate the image
    convert -size 1000x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,50 'VALID_DEPENDENCIES: GATEWAY->AUTH, AUTH->USER_DB, GATEWAY->PAYMENT, PAYMENT->LEDGER, PAYMENT->FRAUD'" /app/sec_graph.png

    # Create the oracle
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <sstream>

std::string urlDecode(const std::string& str) {
    std::string ret;
    char ch;
    int i, ii, len = str.length();
    for (i=0; i < len; i++){
        if(str[i] == '%'){
            sscanf(str.substr(i + 1, 2).c_str(), "%x", &ii);
            ch = static_cast<char>(ii);
            ret += ch;
            i = i + 2;
        } else if(str[i] == '+'){
            ret += ' ';
        } else {
            ret += str[i];
        }
    }
    return ret;
}

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string input = argv[1];
    std::string decoded = urlDecode(input);

    std::unordered_map<std::string, std::unordered_set<std::string>> graph = {
        {"GATEWAY", {"AUTH", "PAYMENT"}},
        {"AUTH", {"USER_DB"}},
        {"PAYMENT", {"LEDGER", "FRAUD"}}
    };

    std::vector<std::string> nodes;
    std::stringstream ss(decoded);
    std::string item;
    while (std::getline(ss, item, ',')) {
        nodes.push_back(item);
    }

    if (nodes.empty()) {
        std::cout << "ALLOW\n";
        return 0;
    }

    std::unordered_set<std::string> all_nodes = {"GATEWAY", "AUTH", "USER_DB", "PAYMENT", "LEDGER", "FRAUD"};
    if (all_nodes.find(nodes[0]) == all_nodes.end()) {
        std::cout << "DENY:" << nodes[0] << "\n";
        return 0;
    }

    for (size_t i = 0; i < nodes.size() - 1; ++i) {
        std::string u = nodes[i];
        std::string v = nodes[i+1];
        if (graph[u].find(v) == graph[u].end()) {
            std::cout << "DENY:" << v << "\n";
            return 0;
        }
    }

    std::cout << "ALLOW\n";
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/oracle.cpp -o /app/oracle_auth_checker
    rm /app/oracle.cpp
    chmod +x /app/oracle_auth_checker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
