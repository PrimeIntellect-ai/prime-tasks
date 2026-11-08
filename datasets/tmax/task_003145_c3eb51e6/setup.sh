#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/librouteconf-2.1.0/include
    mkdir -p /app/librouteconf-2.1.0/src
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/librouteconf-2.1.0/include/routeconf.h
#ifndef ROUTECONF_H
#define ROUTECONF_H
#include <string>
#include <stdexcept>

class RouteConf {
public:
    static std::string parse_and_format(const std::string& input);
};
#endif
EOF

    cat << 'EOF' > /app/librouteconf-2.1.0/src/parser.cpp
#include "routeconf.h"
#include <vector>

std::string RouteConf::parse_and_format(const std::string& input) {
    if (input.find("INVALID") != std::string::npos) {
        throw std::runtime_error("Invalid configuration");
    }

    std::string result;
    std::string cur = input;
    size_t end = cur.find("->");
    std::vector<std::string> tokens;

    while (end != std::string::npos) {
        tokens.push_back(cur.substr(0, end));
        cur = cur.substr(end + 2);
        end = cur.find("->");
    }
    tokens.push_back(cur);

    for (size_t i = 0; i < tokens.size(); ++i) {
        std::string t = tokens[i];
#ifndef BROKEN_WHITESPACE_PARSING
        size_t first = t.find_first_not_of(" \t\n\r");
        if (first == std::string::npos) {
            t = "";
        } else {
            size_t last = t.find_last_not_of(" \t\n\r");
            t = t.substr(first, (last - first + 1));
        }
#endif
        if (i > 0) result += " -> ";
        result += t;
    }
    return result;
}
EOF

    cat << 'EOF' > /app/librouteconf-2.1.0/Makefile
CXX = g++
CXXFLAGS = -fPIC -Iinclude -DBROKEN_WHITESPACE_PARSING=1
LDFLAGS = -shared

all: librouteconf.so

librouteconf.so: src/parser.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $<

install: librouteconf.so
	cp librouteconf.so /usr/local/lib/
	cp include/routeconf.h /usr/local/include/
	ldconfig

clean:
	rm -f librouteconf.so
EOF

    cat << 'EOF' > /tmp/oracle.cpp
#include "routeconf.h"
#include <iostream>
#include <string>

int main() {
    std::string input;
    if (!std::getline(std::cin, input)) {
        return 1;
    }
    try {
        std::string output = RouteConf::parse_and_format(input);
        std::cout << output << std::endl;
        return 0;
    } catch (...) {
        return 1;
    }
}
EOF

    g++ -I/app/librouteconf-2.1.0/include /tmp/oracle.cpp /app/librouteconf-2.1.0/src/parser.cpp -o /opt/oracle/route_canonicalizer
    strip /opt/oracle/route_canonicalizer
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
