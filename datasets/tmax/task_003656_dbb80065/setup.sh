#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ make python3-pil
    pip3 install pytest

    mkdir -p /app/validator
    mkdir -p /opt/oracle

    # Generate diagram.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = 'login -> mfa\nmfa -> session\nsession -> resource\nreset -> email\nemail -> session'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/diagram.png')
"

    # Create graph.h
    cat << 'EOF' > /app/validator/graph.h
#ifndef GRAPH_H
#define GRAPH_H
#include <vector>
#include <string>
class Graph {
public:
    void add_edge(const std::string& src, const std::string& dest);
    bool validate_path(const std::vector<std::string>& path);
};
extern Graph graph;
void initialize_graph();
#endif
EOF

    # Create main.cpp
    cat << 'EOF' > /app/validator/main.cpp
#include "graph.h"
#include <iostream>
#include <vector>
#include <string>
#include <thread>

void dummy() {}

int main(int argc, char** argv) {
    std::thread t(dummy);
    t.join();

    initialize_graph();
    std::vector<std::string> path;
    for (int i = 1; i < argc; ++i) {
        path.push_back(argv[i]);
    }
    if (path.empty() || graph.validate_path(path)) {
        std::cout << "VALID" << std::endl;
    } else {
        std::cout << "INVALID" << std::endl;
    }
    return 0;
}
EOF

    # Create graph_config.cpp
    cat << 'EOF' > /app/validator/graph_config.cpp
#include "graph.h"
#include <map>
#include <set>

std::map<std::string, std::set<std::string>> edges;

void Graph::add_edge(const std::string& src, const std::string& dest) {
    edges[src].insert(dest);
}

bool Graph::validate_path(const std::vector<std::string>& path) {
    if (path.empty() || path.size() == 1) return true;
    for (size_t i = 0; i < path.size() - 1; ++i) {
        if (edges[path[i]].find(path[i+1]) == edges[path[i]].end()) {
            return false;
        }
    }
    return true;
}

Graph graph;

void initialize_graph() {
    // Add edges here
}
EOF

    # Create Makefile with intentional linking error
    cat << 'EOF' > /app/validator/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -pthread

api_validator: main.o graph_config.o
	$(CXX) $(CXXFLAGS) -lpthread main.o graph_config.o -o api_validator

main.o: main.cpp graph.h
	$(CXX) $(CXXFLAGS) -c main.cpp

graph_config.o: graph_config.cpp graph.h
	$(CXX) $(CXXFLAGS) -c graph_config.cpp

clean:
	rm -f *.o api_validator
EOF

    # Create Oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <vector>
#include <string>
#include <map>
#include <set>

int main(int argc, char** argv) {
    std::map<std::string, std::set<std::string>> edges;
    edges["login"].insert("mfa");
    edges["mfa"].insert("session");
    edges["session"].insert("resource");
    edges["reset"].insert("email");
    edges["email"].insert("session");

    std::vector<std::string> path;
    for (int i = 1; i < argc; ++i) {
        path.push_back(argv[i]);
    }
    if (path.empty() || path.size() == 1) {
        std::cout << "VALID" << std::endl;
        return 0;
    }
    for (size_t i = 0; i < path.size() - 1; ++i) {
        if (edges[path[i]].find(path[i+1]) == edges[path[i]].end()) {
            std::cout << "INVALID" << std::endl;
            return 0;
        }
    }
    std::cout << "VALID" << std::endl;
    return 0;
}
EOF

    g++ -std=c++11 /opt/oracle/oracle.cpp -o /opt/oracle/api_validator_oracle
    chmod +x /opt/oracle/api_validator_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
