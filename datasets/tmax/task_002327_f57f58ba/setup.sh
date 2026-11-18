#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /app/vendored/simple-graph-db/src
    mkdir -p /app/data

    cat << 'EOF' > /app/vendored/simple-graph-db/Makefile
CXX = g++
CXXFLAGS = -O3 -std=c++11 -pthread
LDFLAGS = -pthread

all: build/graph_server

build/graph_server: src/main.cpp src/query_handler.cpp
	mkdir -p build
	$(CXX) $(CXXFLAGS) src/main.cpp src/query_handler.cpp -o build/graph_server $(LDFLAGS)

clean:
	rm -rf build
EOF

    cat << 'EOF' > /app/vendored/simple-graph-db/src/main.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

std::string handle_query(int limit, int offset);
void load_graph(const std::string& path);

int main(int argc, char* argv[]) {
    std::string graph_path = "";
    int port = 8080;
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--port" && i + 1 < argc) port = std::stoi(argv[++i]);
        if (std::string(argv[i]) == "--graph" && i + 1 < argc) graph_path = argv[++i];
    }
    if (graph_path.empty()) { std::cerr << "Missing --graph\n"; return 1; }

    load_graph(graph_path);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_fd, (struct sockaddr*)&address, sizeof(address));
    listen(server_fd, 3);

    while (true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        if (new_socket < 0) continue;
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        std::string req(buffer);
        int limit = 10, offset = 0;

        size_t pos = req.find("GET /api/top_centrality?");
        if (pos != std::string::npos) {
            size_t end = req.find(" HTTP/");
            std::string qs = req.substr(pos + 24, end - (pos + 24));

            size_t l_pos = qs.find("limit=");
            if (l_pos != std::string::npos) limit = std::stoi(qs.substr(l_pos + 6));

            size_t o_pos = qs.find("offset=");
            if (o_pos != std::string::npos) offset = std::stoi(qs.substr(o_pos + 7));

            std::string resp_body = handle_query(limit, offset);
            std::string resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + 
                               std::to_string(resp_body.length()) + "\r\n\r\n" + resp_body;
            send(new_socket, resp.c_str(), resp.length(), 0);
        } else {
            std::string resp = "HTTP/1.1 404 Not Found\r\n\r\n";
            send(new_socket, resp.c_str(), resp.length(), 0);
        }
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/vendored/simple-graph-db/src/query_handler.cpp
#include <string>
#include <vector>
#include <algorithm>
#include <string_view>
#include <optional>
#include <iostream>

struct Node {
    int id;
    double score;
};

std::vector<Node> nodes;

void load_graph(const std::string& path) {
    for(int i=1; i<=20; ++i) {
        nodes.push_back({i, 20.0 - i});
    }
}

struct ResultSet {
    std::vector<Node> data;
    std::vector<Node> slice(int offset, int limit) {
        std::vector<Node> res;
        int start = std::min(offset, (int)data.size());
        int end = std::min(start + limit, (int)data.size());
        for (int i = start; i < end; ++i) res.push_back(data[i]);
        return res;
    }
};

std::string handle_query(int limit, int offset) {
    std::optional<int> opt_limit = limit;
    std::string_view sv = "query";

    ResultSet sorted_results{nodes};
    auto paginated = sorted_results.slice(0, limit);

    std::string json = "[";
    for (size_t i = 0; i < paginated.size(); ++i) {
        json += "{\"id\":" + std::to_string(paginated[i].id) + ",\"score\":" + std::to_string(paginated[i].score) + "}";
        if (i < paginated.size() - 1) json += ",";
    }
    json += "]";
    return json;
}
EOF

    cat << 'EOF' > /app/data/edges.csv
source,target
1,2
2,3
3,4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
