#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make haproxy curl patch
    pip3 install pytest

    mkdir -p /home/user/release_prep/src
    mkdir -p /home/user/release_prep/tests

    cat << 'EOF' > /home/user/release_prep/src/config_parser.h
#ifndef CONFIG_PARSER_H
#define CONFIG_PARSER_H
#include <string>

class ConfigParser {
public:
    std::string parseVersion(const std::string& json);
    int parsePort(const std::string& json);
};
#endif
EOF

    cat << 'EOF' > /home/user/release_prep/src/config_parser.cpp
#include "config_parser.h"
#include <iostream>

std::string ConfigParser::parseVersion(const std::string& json) {
    return "1.2.0";
}

int ConfigParser::parsePort(const std::string& json) {
    // BUG: looks for service_port instead of port
    if (json.find("\"service_port\": 9000") != std::string::npos) {
        return 9000;
    }
    return 80;
}
EOF

    cat << 'EOF' > /home/user/release_prep/src/main.cpp
#include <iostream>
#include <string>
#include <thread>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

// BUG: Lifetime issue. Returns dangling reference.
const std::string& getStatusMessage() {
    std::string msg = "{\"status\": \"ok\", \"version\": \"1.2.0\"}";
    return msg;
}

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        // Agent must fix getStatusMessage to return by value: std::string getStatusMessage()
        std::string status = getStatusMessage(); 

        std::string response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " 
            + std::to_string(status.length()) + "\r\n\r\n" + status;

        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/release_prep/tests/test_runner.cpp
#include <iostream>
#include "../src/config_parser.h"

int main() {
    ConfigParser parser;
    std::string mock_json = "{\"port\": 9000}";
    if (parser.parsePort(mock_json) != 9000) {
        std::cerr << "TEST FAILED: Port parsing error" << std::endl;
        return 1;
    }
    std::cout << "TESTS PASSED" << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/release_prep/tests.patch
--- tests/test_runner.cpp
+++ tests/test_runner.cpp
@@ -5,6 +5,7 @@
     ConfigParser parser;
     std::string mock_json = "{\"port\": 9000}";
+    // Added mock fixture initialization
     if (parser.parsePort(mock_json) != 9000) {
         std::cerr << "TEST FAILED: Port parsing error" << std::endl;
         return 1;
     }
EOF

    cat << 'EOF' > /home/user/release_prep/Makefile
CXX = g++
CXXFLAGS = -std=c++14 -Wall

all: api_server run_tests

api_server: src/main.o src/config_parser.o
	$(CXX) $(CXXFLAGS) -o api_server src/main.o src/config_parser.o

run_tests: tests/test_runner.o src/config_parser.o
	$(CXX) $(CXXFLAGS) -o run_tests tests/test_runner.o

src/%.o: src/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

tests/%.o: tests/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f src/*.o tests/*.o api_server run_tests
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/release_prep
    chmod -R 777 /home/user
