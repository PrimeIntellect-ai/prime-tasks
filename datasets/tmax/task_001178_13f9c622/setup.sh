#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/deploy/src
    mkdir -p /home/user/deploy/data/in
    mkdir -p /home/user/deploy/data/out
    mkdir -p /home/user/deploy/logs
    mkdir -p /home/user/deploy/bin
    mkdir -p /home/user/deploy/scripts
    mkdir -p /home/user/deploy/run

    cat << 'EOF' > /home/user/deploy/src/processor.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <filesystem>
#include <chrono>
#include <thread>

namespace fs = std::filesystem;

void log_message(const std::string& msg) {
    std::ofstream log_file("/home/user/deploy/logs/system.log", std::ios_base::app);
    log_file << msg << std::endl;
}

int main() {
    std::string in_dir = "/home/user/deploy/data/in/";
    std::string out_dir = "/home/user/deploy/data/out/";

    while (true) {
        log_message("HEARTBEAT: " + std::to_string(std::time(nullptr)));

        for (const auto& entry : fs::directory_iterator(in_dir)) {
            if (entry.is_regular_file()) {
                std::ifstream infile(entry.path());
                std::string content((std::istreambuf_iterator<char>(infile)), std::istreambuf_iterator<char>());

                if (content.find("POISON_PILL") != std::string::npos) {
                    // BUG: Intentional crash
                    std::cerr << "FATAL: Poison pill encountered!" << std::endl;
                    std::abort();
                }

                std::ofstream outfile(out_dir + entry.path().filename().string());
                outfile << content << " PROCESSED";

                log_message("SUCCESS: Processed " + entry.path().filename().string());
                fs::remove(entry.path());
            }
        }
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    return 0;
}
EOF

    echo "Normal data 1" > /home/user/deploy/data/in/file1.txt
    echo "Normal data 2" > /home/user/deploy/data/in/file2.txt
    echo "POISON_PILL data" > /home/user/deploy/data/in/file3.txt
    echo "Normal data 4" > /home/user/deploy/data/in/file4.txt
    echo "Normal data 5" > /home/user/deploy/data/in/file5.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/deploy
    chmod -R 777 /home/user
