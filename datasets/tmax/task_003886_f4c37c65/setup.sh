#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/query_processor.cpp
#include <iostream>
#include <string>
#include <vector>

void process_query(const std::string& query) {
    std::vector<std::string> tokens;
    size_t pos = 0;
    while (pos < query.length()) {
        size_t next = query.find('&', pos);
        if (next == std::string::npos) {
            tokens.push_back(query.substr(pos));
            break;
        }
        tokens.push_back(query.substr(pos, next - pos));
        pos = next + 1;
    }

    for (const auto& token : tokens) {
        size_t eq = token.find('=');
        // Bug: if eq is std::string::npos, token.substr(eq + 1) will throw out_of_range
        std::string key = token.substr(0, eq);
        std::string val = token.substr(eq + 1);
        std::cout << "K:" << key << " V:" << val << std::endl;
    }
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    process_query(argv[1]);
    return 0;
}
EOF

    chmod -R 777 /home/user
