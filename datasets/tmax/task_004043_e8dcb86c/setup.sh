#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak
    pip3 install pytest

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/sanitizer_oracle.cpp
#include <iostream>
#include <string>
#include <vector>

std::string normalize_path(const std::string& path) {
    std::vector<std::string> parts;
    std::string current;
    for (char c : path) {
        if (c == '/') {
            if (!current.empty() && current != ".") {
                if (current == "..") {
                    if (!parts.empty()) parts.pop_back();
                } else {
                    parts.push_back(current);
                }
            }
            current.clear();
        } else {
            current += c;
        }
    }
    if (!current.empty() && current != ".") {
        if (current == "..") {
            if (!parts.empty()) parts.pop_back();
        } else {
            parts.push_back(current);
        }
    }
    std::string res = "";
    if (path.length() > 0 && path[0] == '/') res += "/";
    for (size_t i = 0; i < parts.size(); ++i) {
        res += parts[i];
        if (i < parts.size() - 1) res += "/";
    }
    if (res.empty()) return "/";
    return res;
}

int main() {
    std::string line;
    std::string current_path = "";
    while (std::getline(std::cin, line)) {
        if (line.rfind("Path: ", 0) == 0) {
            current_path = line.substr(6);
        } else if (line == "RECORD END") {
            if (!current_path.empty()) {
                std::string norm = normalize_path(current_path);
                bool rejected = false;

                if (norm.rfind("/mnt/storage", 0) != 0 || (norm.length() > 12 && norm[12] != '/')) {
                    rejected = true;
                }

                if (current_path.length() >= 4 && current_path.substr(current_path.length() - 4) == ".tmp") {
                    rejected = true;
                }

                if (rejected) {
                    std::cout << "REJECTED: " << current_path << "\n";
                } else {
                    std::cout << "ACCEPTED: " << norm << "\n";
                }
                current_path = "";
            }
        }
    }
    return 0;
}
EOF
    g++ -O3 /opt/oracle/sanitizer_oracle.cpp -o /opt/oracle/sanitizer_oracle

    mkdir -p /app
    espeak -w /app/admin_instructions.wav "The base directory is /mnt/storage. You must reject any path that escapes this base directory. Also, ignore and reject any records where the file path ends with .tmp."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
