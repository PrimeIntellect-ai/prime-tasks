#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential curl
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > solver.h
#ifndef SOLVER_H
#define SOLVER_H

#ifdef __cplusplus
extern "C" {
#endif

// Returns true if the manifest satisfies the expression constraints
bool evaluate_constraints(const char* expr, const char* manifest);

#ifdef __cplusplus
}
#endif

#endif
EOF

    cat << 'EOF' > solver.cpp
#include "solver.h"
#include <string>
#include <map>
#include <vector>
#include <sstream>

bool evaluate_constraints(const char* expr, const char* manifest) {
    std::string e(expr);
    std::string m(manifest);

    std::map<std::string, int> man_map;
    std::stringstream mss(m);
    std::string m_item;
    while (std::getline(mss, m_item, ',')) {
        size_t colon = m_item.find(':');
        if (colon != std::string::npos) {
            man_map[m_item.substr(0, colon)] = std::stoi(m_item.substr(colon + 1));
        }
    }

    std::stringstream ess(e);
    std::string e_item;
    while (std::getline(ess, e_item, ',')) {
        size_t op_pos = e_item.find(">=");
        if (op_pos != std::string::npos) {
            std::string key = e_item.substr(0, op_pos);
            int val = std::stoi(e_item.substr(op_pos + 2));
            if (man_map.find(key) == man_map.end() || man_map[key] < val) return false;
            continue;
        }
        op_pos = e_item.find("==");
        if (op_pos != std::string::npos) {
            std::string key = e_item.substr(0, op_pos);
            int val = std::stoi(e_item.substr(op_pos + 2));
            if (man_map.find(key) == man_map.end() || man_map[key] != val) return false;
            continue;
        }
    }
    return true;
}
EOF

    cat << 'EOF' > http_stub.h
#ifndef HTTP_STUB_H
#define HTTP_STUB_H

#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>
#include <functional>

void start_server(int port, std::function<std::pair<int, std::string>(const std::string&)> handler) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[2048] = {0};
        read(new_socket, buffer, 2048);

        std::string req(buffer);
        size_t body_pos = req.find("\r\n\r\n");
        std::string body = "";
        if (body_pos != std::string::npos) {
            body = req.substr(body_pos + 4);
        }

        auto res = handler(body);

        std::string header = "HTTP/1.1 " + std::to_string(res.first) + " OK\r\nContent-Type: application/json\r\n\r\n";
        std::string response = header + res.second;

        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }
}
#endif
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
