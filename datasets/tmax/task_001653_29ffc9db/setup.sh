#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make
    pip3 install pytest

    mkdir -p /home/user/emulator_port

    cat << 'EOF' > /home/user/emulator_port/bf_interpreter.hpp
#pragma once
#include <string>
#include <vector>

inline std::string execute_bf(const std::string& code) {
    std::string output;
    std::vector<uint8_t> tape(30000, 0);
    int ptr = 0;
    int max_steps = 100000;
    int steps = 0;

    for (size_t i = 0; i < code.size() && steps < max_steps; ++i, ++steps) {
        char c = code[i];
        if (c == '>') { ptr = (ptr + 1) % 30000; }
        else if (c == '<') { ptr = (ptr - 1 + 30000) % 30000; }
        else if (c == '+') { tape[ptr]++; }
        else if (c == '-') { tape[ptr]--; }
        else if (c == '.') { output += static_cast<char>(tape[ptr]); }
        else if (c == '[') {
            if (tape[ptr] == 0) {
                int loop = 1;
                while (loop > 0 && ++i < code.size()) {
                    if (code[i] == '[') loop++;
                    else if (code[i] == ']') loop--;
                }
            }
        }
        else if (c == ']') {
            if (tape[ptr] != 0) {
                int loop = 1;
                while (loop > 0 && --i >= 0) {
                    if (code[i] == ']') loop++;
                    else if (code[i] == '[') loop--;
                }
            }
        }
    }
    return output;
}
EOF

    cat << 'EOF' > /home/user/emulator_port/server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>
#include <thread>
#include "bf_interpreter.hpp"

void handle_client(int client_fd) {
    char buffer[1024] = {0};
    read(client_fd, buffer, 1024);
    std::string request(buffer);

    // TODO: Parse request, validate code, and return HTTP response
    // Hint: Look for "GET /execute?code=" in the request
    // Hint: Return 400 Bad Request for invalid characters

    std::string response = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n";
    send(client_fd, response.c_str(), response.length(), 0);
    close(client_fd);
}

int main() {
    int server_fd;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while (true) {
        int client_fd = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        if (client_fd >= 0) {
            std::thread(handle_client, client_fd).detach();
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/emulator_port/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(BFServer)

# Missing CXX standard 17
# Missing Threads package

add_executable(bf_server server.cpp)
# target_link_libraries(bf_server Threads::Threads) # this is missing
EOF

    cat << 'EOF' > /home/user/emulator_port/benchmark.py
import urllib.request
import time
import sys

def test_url(url, expect_status):
    try:
        req = urllib.request.urlopen(url)
        content = req.read().decode('utf-8')
        return req.status == expect_status, content
    except urllib.error.HTTPError as e:
        return e.code == expect_status, e.read().decode('utf-8')
    except Exception as e:
        return False, str(e)

success = 0
tests = [
    ("http://127.0.0.1:8080/execute?code=++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.", 200),
    ("http://127.0.0.1:8080/execute?code=++[>++<-]a", 400)
]

for url, status in tests:
    res, content = test_url(url, status)
    if res:
        success += 1
        print(f"PASS: {url} -> {status}")
    else:
        print(f"FAIL: {url} (Expected {status}, Got {content})")

if success == len(tests):
    print("BENCHMARK_COMPLETE: ALL PASS")
    sys.exit(0)
else:
    print("BENCHMARK_COMPLETE: FAIL")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
