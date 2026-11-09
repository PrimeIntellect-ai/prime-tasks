#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/log_writer.cpp
#include <iostream>
#include <string>
#include <chrono>
#include <thread>
#include <sys/file.h>
#include <unistd.h>
#include <fcntl.h>
#include <iomanip>
#include <sstream>

std::string string_to_hex_utf16le(const std::string& str) {
    std::ostringstream oss;
    for (char c : str) {
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)c;
        oss << "00";
    }
    return oss.str();
}

int main(int argc, char* argv[]) {
    std::string log_dir = "/home/user/logs";
    if (argc > 1) {
        log_dir = argv[1];
    }
    std::string active_path = log_dir + "/active.log";
    std::string rotated_path = log_dir + "/rotated.log";

    for (int i = 0; i < 5000; ++i) {
        int fd = open(active_path.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (fd != -1) {
            flock(fd, LOCK_EX);
            std::string text = "Log entry " + std::to_string(i);
            std::string hex_data = string_to_hex_utf16le(text);
            std::string json = "{\"seq\": " + std::to_string(i) + ", \"data\": \"" + hex_data + "\"}\n";
            auto res = write(fd, json.c_str(), json.length());
            (void)res;
            flock(fd, LOCK_UN);
            close(fd);
        }

        if ((i + 1) % 100 == 0) {
            int fd2 = open(active_path.c_str(), O_RDWR);
            if (fd2 != -1) {
                flock(fd2, LOCK_EX);
                rename(active_path.c_str(), rotated_path.c_str());
                flock(fd2, LOCK_UN);
                close(fd2);
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return 0;
}
EOF

    g++ -O3 -std=c++17 /tmp/log_writer.cpp -o /app/log_writer
    strip /app/log_writer
    rm /tmp/log_writer.cpp

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logs

    chmod -R 777 /home/user
