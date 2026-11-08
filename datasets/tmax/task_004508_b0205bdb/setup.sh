#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/log_processor
    cd /home/user/log_processor

    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -std=c++17 -Wall

all: processor

processor: main.o parser.o validator.o
	$(CXX) $(CXXFLAGS) -o processor main.o parser.o validator.o

main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp

parser.o: parser.cpp parser.h
	$(CXX) $(CXXFLAGS) -c parser.cpp

validator.o: validator.cpp validator.h
	$(CXX) $(CXXFLAGS) -c validator.cpp

clean:
	rm -f *.o processor
EOF

    cat << 'EOF' > types.h
#pragma once
#include <string>

struct Request {
    double timestamp;
    std::string user_id;
    std::string payload_hex;
    std::string checksum_hex;
    std::string status;
};
EOF

    cat << 'EOF' > parser.h
#pragma once
#include <string>
#include <vector>
#include "types.h"
#include "validator.h"

class Parser {
public:
    Validator validator;
    std::vector<Request> parseFile(const std::string& filename);
    void writeFile(const std::string& filename, const std::vector<Request>& requests);
};
EOF

    cat << 'EOF' > validator.h
#pragma once
#include <string>
#include <vector>
#include <map>
#include "types.h"
#include "parser.h"

class Validator {
private:
    std::map<std::string, std::vector<double>> user_requests;
public:
    void process(Request& req);
};
EOF

    cat << 'EOF' > parser.cpp
#include "parser.h"
#include <fstream>
#include <sstream>

std::vector<Request> Parser::parseFile(const std::string& filename) {
    std::vector<Request> requests;
    std::ifstream file(filename);
    std::string line;
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string ts, uid, payload, chk;
        std::getline(ss, ts, ',');
        std::getline(ss, uid, ',');
        std::getline(ss, payload, ',');
        std::getline(ss, chk, ',');

        Request req;
        req.timestamp = std::stod(ts);
        req.user_id = uid;
        req.payload_hex = payload;
        req.checksum_hex = chk;

        validator.process(req);
        requests.push_back(req);
    }
    return requests;
}

void Parser::writeFile(const std::string& filename, const std::vector<Request>& requests) {
    std::ofstream file(filename);
    for (const auto& req : requests) {
        file << std::fixed << req.timestamp << ","
             << req.user_id << ","
             << req.payload_hex << ","
             << req.checksum_hex << ","
             << req.status << "\n";
    }
}
EOF

    cat << 'EOF' > validator.cpp
#include "validator.h"

// TODO: Implement checksum validation and rate limiting.
void Validator::process(Request& req) {
    // Dummy implementation. Replace this!
    req.status = "OK"; 
}
EOF

    cat << 'EOF' > main.cpp
#include "parser.h"
#include <iostream>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <input.csv> <output.csv>\n";
        return 1;
    }
    Parser p;
    auto reqs = p.parseFile(argv[1]);
    p.writeFile(argv[2], reqs);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/requests.csv
1600000000.1,userA,010203,00
1600000000.2,userA,010203,00
1600000000.3,userA,ff01,fe
1600000000.4,userA,1020,30
1600000000.5,userA,1020,30
1600000000.6,userB,01,01
1600000000.7,userB,01,02
1600000001.2,userA,01,01
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
