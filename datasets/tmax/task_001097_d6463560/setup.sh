#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev ffmpeg
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <sstream>
#include <vector>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main() {
    json root = json::object();
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        std::istringstream iss(line);
        std::string ts, action, path;
        long long size;
        iss >> ts >> action >> path >> size;
        if (path.empty() || path[0] != '/') continue;

        std::vector<std::string> parts;
        std::string part;
        for (size_t i = 1; i < path.size(); ++i) {
            if (path[i] == '/') {
                if (!part.empty()) {
                    parts.push_back(part);
                    part.clear();
                }
            } else {
                part += path[i];
            }
        }
        if (!part.empty()) parts.push_back(part);

        if (parts.empty()) continue;

        json* current = &root;
        for (size_t i = 0; i < parts.size() - 1; ++i) {
            if (!current->contains(parts[i]) || !(*current)[parts[i]].is_object()) {
                (*current)[parts[i]] = json::object();
            }
            current = &((*current)[parts[i]]);
        }

        std::string filename = parts.back();
        if (action == "CREATE" || action == "MODIFY") {
            (*current)[filename] = size;
        } else if (action == "DELETE") {
            current->erase(filename);
        }
    }
    std::cout << root.dump() << std::endl;
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/oracle.cpp -o /app/oracle_tracker_hidden
    rm /app/oracle.cpp

    # Use matroska format for attachments, but name it .mp4 as requested
    ffmpeg -f lavfi -i testsrc=duration=1:size=640x480:rate=30 -attach /app/oracle_tracker_hidden -metadata:s:t mimetype=application/octet-stream -metadata:s:t filename=oracle_tracker -c:v libx264 -f matroska -y /app/screencast.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
