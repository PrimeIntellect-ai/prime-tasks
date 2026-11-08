#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /app/tinyhttp
cat << 'EOF' > /app/tinyhttp/tinyhttp.h
#pragma once
#include <string>
#include <functional>
#include <map>

struct Request {
    std::string method;
    std::string path;
    std::string body;
    std::map<std::string, std::string> headers;
};

struct Response {
    int status = 200;
    std::string body;
};

class Server {
public:
    void Post(const std::string& path, std::function<void(const Request&, Response&)> handler);
    void listen(const std::string& host, int port);
private:
    std::map<std::string, std::function<void(const Request&, Response&)>> post_handlers;
};
EOF

cat << 'EOF' > /app/tinyhttp/parser.cpp
#include "tinyhttp.h"
#include <iostream>
// Mocked down parser for simplicity that reads HTTP requests
// The deliberate bug:
int parse_content_length(const std::string& val) {
    int len = 0;
    for(char c : val) {
        if(c >= '0' && c <= '9') {
            len = len * 10 + (c - '1'); // BUG: should be '0'
        }
    }
    return len;
}
EOF

cat << 'EOF' > /app/tinyhttp/tinyhttp.cpp
#include "tinyhttp.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <thread>
#include <string.h>

extern int parse_content_length(const std::string& val);

void Server::Post(const std::string& path, std::function<void(const Request&, Response&)> handler) {
    post_handlers[path] = handler;
}

void Server::listen(const std::string& host, int port) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    inet_pton(AF_INET, host.c_str(), &address.sin_addr);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    ::listen(server_fd, 3);

    while(true) {
        int client_socket = accept(server_fd, nullptr, nullptr);
        std::thread([this, client_socket]() {
            char buffer[4096] = {0};
            read(client_socket, buffer, 4096);

            // extremely rudimentary mock parsing
            Request req;
            std::string raw(buffer);
            auto line_end = raw.find("\r\n");
            req.method = "POST"; 
            req.path = "/verify";

            auto cl_pos = raw.find("Content-Length: ");
            if(cl_pos != std::string::npos) {
                cl_pos += 16;
                auto cl_end = raw.find("\r\n", cl_pos);
                int len = parse_content_length(raw.substr(cl_pos, cl_end - cl_pos));
                auto body_start = raw.find("\r\n\r\n");
                if(body_start != std::string::npos) {
                    req.body = raw.substr(body_start + 4, len);
                }
            }

            Response res;
            if (post_handlers.count(req.path)) {
                post_handlers[req.path](req, res);
            } else {
                res.status = 404;
            }

            std::string response_str = "HTTP/1.1 " + std::to_string(res.status) + " OK\r\n"
                                     + "Content-Length: " + std::to_string(res.body.length()) + "\r\n\r\n"
                                     + res.body;
            write(client_socket, response_str.c_str(), response_str.length());
            close(client_socket);
        }).detach();
    }
}
EOF

cat << 'EOF' > /app/tinyhttp/Makefile
CXX=g++
CXXFLAGS=-std=c++17 -Wall

all: libtinyhttp.a

tinyhttp.o: tinyhttp.cpp
	$(CXX) $(CXXFLAGS) -c tinyhttp.cpp

parser.o: parser.cpp
	$(CXX) $(CXXFLAGS) -c parser.cpp

libtinyhttp.a: tinyhttp.o parser.o
	ar rcs libtinyhttp.a tinyhttp.o parser.o

clean:
	rm -f *.o *.a
EOF

useradd -m -s /bin/bash user || true
mkdir -p /home/user/verifier
chmod -R 777 /app/tinyhttp
chmod -R 777 /home/user
