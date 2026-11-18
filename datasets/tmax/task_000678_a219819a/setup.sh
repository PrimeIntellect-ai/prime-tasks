#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget curl
    pip3 install pytest requests

    mkdir -p /app/etl-worker/src
    mkdir -p /app/etl-worker/include

    wget https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -O /app/etl-worker/include/httplib.h

    cat << 'EOF' > /app/etl-worker/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -Iinclude
LDFLAGS = 

all: etl_server

etl_server: src/main.o src/extractor.o
	$(CXX) -o $@ $^ $(LDFLAGS)

src/main.o: src/main.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

src/extractor.o: src/extractor.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f src/*.o etl_server
EOF

    cat << 'EOF' > /app/etl-worker/src/extractor.h
#pragma once
#include <string>
#include <vector>

std::vector<std::string> extract_txns(const std::string& text);
EOF

    cat << 'EOF' > /app/etl-worker/src/extractor.cpp
#include "extractor.h"
#include <regex>

std::vector<std::string> extract_txns(const std::string& text) {
    std::vector<std::string> results;
    std::regex pattern("TXN-[A-Z]{3}-[0-9]{4}");

    auto words_begin = std::sregex_iterator(text.begin(), text.end(), pattern);
    auto words_end = std::sregex_iterator();

    for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
        results.push_back(i->str());
    }
    return results;
}
EOF

    cat << 'EOF' > /app/etl-worker/src/main.cpp
#include <iostream>
#include <string>
#include <vector>
#include <future>
#include "httplib.h"
#include "extractor.h"

int main(int argc, char** argv) {
    std::string host = "127.0.0.1";
    int port = 8080;

    if (argc >= 3) {
        host = argv[1];
        port = std::stoi(argv[2]);
    }

    httplib::Server svr;

    svr.Post("/extract", [](const httplib::Request& req, httplib::Response& res) {
        std::string body = req.body;

        auto future = std::async(std::launch::async, [&body]() {
            return extract_txns(body);
        });

        std::vector<std::string> txns = future.get();

        std::string json = "[";
        for (size_t i = 0; i < txns.size(); ++i) {
            json += "\"" + txns[i] + "\"";
            if (i < txns.size() - 1) json += ", ";
        }
        json += "]";

        res.set_content(json, "application/json");
    });

    std::cout << "Starting server on " << host << ":" << port << std::endl;
    svr.listen(host, port);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/etl-worker
