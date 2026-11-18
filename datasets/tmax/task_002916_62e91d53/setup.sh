#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++ make ffmpeg imagemagick
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/signal_decoder

    # Generate the base C++ code for oracle
    cat << 'EOF' > /app/base.cpp
#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <algorithm>

std::mutex mtx;
std::vector<std::string> results;

void process_chunk(const std::string& hex_chunk, int index) {
    std::string ascii = "";
    for (size_t i = 0; i < hex_chunk.length(); i += 2) {
        std::string byteString = hex_chunk.substr(i, 2);
        char byte = (char) strtol(byteString.c_str(), NULL, 16);
        ascii += byte;
    }
    mtx.lock();
    results.push_back(std::to_string(index) + ":" + ascii);
    mtx.unlock();
}

int main() {
    std::string input;
    if (!(std::cin >> input)) return 0;

    size_t chunk_size = 16; 

    std::vector<std::thread> threads;
    int idx = 0;
    for (size_t i = 0; i < input.length(); i += chunk_size) {
        std::string chunk = input.substr(i, chunk_size);
        threads.push_back(std::thread(process_chunk, chunk, idx++));
    }

    for (auto& t : threads) {
        t.join();
    }

    std::sort(results.begin(), results.end(), [](const std::string& a, const std::string& b) {
        int ia = std::stoi(a.substr(0, a.find(':')));
        int ib = std::stoi(b.substr(0, b.find(':')));
        return ia < ib;
    });

    for (const auto& res : results) {
        std::cout << res.substr(res.find(':') + 1);
    }
    std::cout << std::endl;
    return 0;
}
EOF

    # Compile Oracle
    g++ -O3 -pthread /app/base.cpp -o /app/oracle_decoder

    # Set up Git repo
    cd /home/user/signal_decoder
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cp /app/base.cpp decoder.cpp
    cat << 'EOF' > Makefile
signal_decoder: decoder.cpp
	g++ -O3 -pthread decoder.cpp -o signal_decoder
EOF
    git add .
    git commit -m "Initial commit"

    for i in {1..5}; do
        echo "// comment $i" >> decoder.cpp
        git commit -am "Dummy commit $i"
    done

    # Logic bug
    sed -i 's/size_t chunk_size = 16;/size_t chunk_size = 14;/' decoder.cpp
    git commit -am "Optimize chunk size"

    for i in {6..10}; do
        echo "// comment $i" >> decoder.cpp
        git commit -am "Dummy commit $i"
    done

    # Concurrency bug
    sed -i 's/mtx.lock();/\/\/ mtx.lock();/' decoder.cpp
    sed -i 's/mtx.unlock();/\/\/ mtx.unlock();/' decoder.cpp
    git commit -am "Remove locks for performance"

    # Makefile bug
    sed -i 's/-pthread//' Makefile
    git commit -am "Clean up Makefile"

    # Generate Video
    cd /app
    cat << 'EOF' > gen_video.py
import os
import subprocess

payload = "48656c6c6f20576f726c6421204372617368205465737420313233343536"
bits = ""
for char in payload:
    bits += bin(int(char, 16))[2:].zfill(4)

os.makedirs("frames", exist_ok=True)
for i, b in enumerate(bits):
    color = "white" if b == "1" else "black"
    subprocess.run(["convert", "-size", "100x100", f"xc:{color}", f"frames/frame_{i:03d}.png"])

subprocess.run(["ffmpeg", "-framerate", "24", "-i", "frames/frame_%03d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "signal.mp4"])
EOF
    python3 gen_video.py
    rm -rf frames gen_video.py base.cpp

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
