#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make
    pip3 install pytest

    mkdir -p /home/user/project/c_src
    mkdir -p /home/user/project/cpp_src
    mkdir -p /home/user/project/include
    mkdir -p /home/user/project/tests
    mkdir -p /home/user/project/lib
    mkdir -p /home/user/project/bin

    cat << 'EOF' > /home/user/project/include/mathparser.h
#ifndef MATHPARSER_H
#define MATHPARSER_H

double evaluate_rpn(const char* expr);

#endif
EOF

    cat << 'EOF' > /home/user/project/c_src/mathparser.c
#include "mathparser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

double evaluate_rpn(const char* expr) {
    double stack[100];
    int top = -1;
    char buffer[256];
    strncpy(buffer, expr, 255);
    buffer[255] = '\0';

    char *token = strtok(buffer, " \t\n");
    while (token != NULL) {
        if (isdigit(token[0]) || (token[0] == '-' && isdigit(token[1]))) {
            stack[++top] = atof(token);
        } else {
            if (top < 1) return 0.0; // Error
            double a = stack[top--];
            double b = stack[top--];
            if (token[0] == '+') stack[++top] = b + a;
            else if (token[0] == '-') stack[++top] = b - a;
            else if (token[0] == '*') stack[++top] = b * a;
            else if (token[0] == '/') stack[++top] = a / b; // BUG: should be b / a
        }
        token = strtok(NULL, " \t\n");
    }
    return top >= 0 ? stack[top] : 0.0;
}
EOF

    cat << 'EOF' > /home/user/project/cpp_src/server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>
#include "mathparser.h"

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    std::cout << "Server listening on port 8080" << std::endl;

    int new_socket = accept(server_fd, nullptr, nullptr);
    char buffer[1024] = {0};

    while (true) {
        memset(buffer, 0, sizeof(buffer));
        int valread = read(new_socket, buffer, 1024);
        if (valread <= 0) break;

        std::string expr(buffer);
        if (expr.find("QUIT") != std::string::npos) break;

        double result = evaluate_rpn(buffer);
        std::string res_str = std::to_string(result) + "\n";
        send(new_socket, res_str.c_str(), res_str.length(), 0);
    }

    close(new_socket);
    close(server_fd);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/tests/test_client.py
import socket
import time
import sys

def run_tests():
    time.sleep(1) # wait for server to start
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(('127.0.0.1', 8080))
    except Exception as e:
        print("Connection failed:", e)
        sys.exit(1)

    tests = [
        ("3 4 +", 7.0),
        ("10 2 /", 5.0),
        ("5 2 * 3 -", 7.0)
    ]

    success = True
    for expr, expected in tests:
        s.sendall(expr.encode('utf-8'))
        data = s.recv(1024).decode('utf-8').strip()
        try:
            result = float(data)
            if abs(result - expected) > 0.001:
                print(f"FAIL: {expr} = {result}, expected {expected}")
                success = False
            else:
                print(f"PASS: {expr} = {result}")
        except ValueError:
            print(f"FAIL: Invalid response {data}")
            success = False

    s.sendall(b"QUIT")
    s.close()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    run_tests()
EOF

    cat << 'EOF' > /home/user/project/Makefile
CC = gcc
CXX = g++
CFLAGS = -fPIC -I./include
CXXFLAGS = -I./include

all: lib/libmathparser.so bin/server

lib/libmathparser.so: c_src/mathparser.c
	$(CC) $(CFLAGS) -shared -o $@ $<

bin/server: cpp_src/server.cpp lib/libmathparser.so
	$(CXX) $(CXXFLAGS) -o $@ $< -L./lib -lmathparser -Wl,-rpath=./lib

ci: all
	@echo "Starting server..."
	./bin/server & echo $$! > server.pid
	python3 tests/test_client.py; \
	RET=$$?; \
	kill `cat server.pid`; \
	rm server.pid; \
	exit $$RET

clean:
	rm -rf lib/* bin/* server.pid
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
