#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/url_router

    cat << 'EOF' > /home/user/url_router/router.h
#ifndef ROUTER_H
#define ROUTER_H

#include <string>
#include <map>

struct RouteResult {
    std::string path;
    std::map<std::string, std::string> params;
    unsigned int checksum;
};

class Router {
public:
    static RouteResult parse(const std::string& url);
private:
    static unsigned int computeChecksum(const std::string& data);
};

#endif
EOF

    cat << 'EOF' > /home/user/url_router/router.cpp
#include "router.h"
#include <sstream>

unsigned int Router::computeChecksum(const std::string& data) {
    unsigned int hash = 0;
    for (char c : data) {
        hash = hash * 31 + c;
    }
    return hash;
}

RouteResult Router::parse(const std::string& url) {
    RouteResult result;
    size_t q_pos = url.find('?');
    if (q_pos == std::string::npos) {
        result.path = url;
        result.checksum = computeChecksum(url);
        return result;
    }

    result.path = url.substr(0, q_pos);
    std::string query = url.substr(q_pos + 1);

    std::stringstream ss(query);
    std::string pair;
    std::string to_hash = result.path;

    while (std::getline(ss, pair, '&')) {
        size_t eq_pos = pair.find('=');
        // BUG: if eq_pos is npos, or eq_pos is at the end of the string, this throws or misbehaves
        if (eq_pos != std::string::npos) {
            std::string key = pair.substr(0, eq_pos);
            // BUG: out of bounds if eq_pos + 1 > pair.length()
            std::string value = pair.substr(eq_pos + 1);
            result.params[key] = value;
            to_hash += key + value;
        } else {
            result.params[pair] = "";
            to_hash += pair;
        }
    }

    result.checksum = computeChecksum(to_hash);
    return result;
}
EOF

    cat << 'EOF' > /home/user/url_router/main.cpp
#include <iostream>
#include "router.h"

int main(int argc, char** argv) {
    // Agent needs to implement the bench logic here
    return 0;
}
EOF

    cat << 'EOF' > /home/user/url_router/test.cpp
#include <iostream>
#include "router.h"

int main() {
    // Agent needs to implement property-based testing here
    return 0;
}
EOF

    cat << 'EOF' > /home/user/url_router/Makefile
CXX=g++
CXXFLAGS=-std=c++17 -Wall -Wextra -O2

all: router_app router_test

router.o: router.cpp router.h
	$(CXX) $(CXXFLAGS) -c router.cpp -o router.o

main.o: main.cpp router.h
	$(CXX) $(CXXFLAGS) -c main.cpp -o main.o

test.o: test.cpp router.h
	$(CXX) $(CXXFLAGS) -c test.cpp -o test.o

# LINKING ERROR: missing router.o in both targets
router_app: main.o
	$(CXX) $(CXXFLAGS) main.o -o router_app

router_test: test.o
	$(CXX) $(CXXFLAGS) test.o -o router_test

clean:
	rm -f *.o router_app router_test
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
