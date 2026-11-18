#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app
    dd if=/dev/urandom of=/app/experiment_video.mp4 bs=1 count=10000 2>/dev/null

    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

int main() {
    std::ifstream file("/app/experiment_video.mp4", std::ios::binary);
    if (!file) return 1;
    std::vector<unsigned char> data(4096);
    file.read(reinterpret_cast<char*>(data.data()), 4096);

    std::string line;
    while (std::getline(std::cin, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) {
            std::cout << "0,0,0,0\n";
            continue;
        }

        long long emb[4] = {0, 0, 0, 0};
        int L = line.length();
        for (int i = 0; i < 4; ++i) {
            for (int k = 0; k < 1024; ++k) {
                unsigned char byte_val = data[i * 1024 + k];
                unsigned char char_val = line[k % L];
                emb[i] = (emb[i] + byte_val * (char_val + 1)) % 10007;
            }
        }
        std::cout << emb[0] << "," << emb[1] << "," << emb[2] << "," << emb[3] << "\n";
    }
    return 0;
}
EOF

    g++ -O3 /tmp/oracle.cpp -o /app/oracle_embedder
    chmod +x /app/oracle_embedder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
