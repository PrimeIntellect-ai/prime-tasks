#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/proxy_analyzer

    cat << 'EOF' > /home/user/logs.txt
ENDPOINT /login [ 45.2 12.5 + ]
ENDPOINT /data [ 100.0 2.0 / 5.0 + ]
ENDPOINT /calc [ 10.0 3.0 - 2.0 * ]
ENDPOINT /auth [ 5.5 0.5 - 2.0 / ]
EOF

    cat << 'EOF' > /home/user/proxy_analyzer/Makefile
CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra

all: proxy_analyzer

proxy_analyzer: main.o parser.o evaluator.o
	$(CXX) $(CXXFLAGS) -o $@ $^

main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c $<

parser.o: parser.cpp
	$(CXX) $(CXXFLAGS) -c $<

evaluator.o: evaluator.cpp
	$(CXX) $(CXXFLAGS) -c $<

clean:
	rm -f *.o proxy_analyzer
EOF

    cat << 'EOF' > /home/user/proxy_analyzer/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

struct LogEntry {
    std::string endpoint;
    std::vector<std::string> tokens;
};

LogEntry parse_line(const std::string& line);
double evaluate_postfix(const std::vector<std::string>& tokens);

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <logfile>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    std::string line;
    while (std::getline(infile, line)) {
        if (line.empty()) continue;
        LogEntry entry = parse_line(line);
        if (!entry.endpoint.empty()) {
            double result = evaluate_postfix(entry.tokens);
            std::cout << entry.endpoint << " " << result << "\n";
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/proxy_analyzer/parser.cpp
#include <string>
#include <vector>
#include <sstream>

struct LogEntry {
    std::string endpoint;
    std::vector<std::string> tokens;
};

// BUG INTENTIONAL: Using std::string_view pointing to local temporary std::string
LogEntry parse_line(const std::string& line) {
    LogEntry entry;
    std::istringstream iss(line);
    std::string word;

    iss >> word; // ENDPOINT
    iss >> entry.endpoint; // /path

    iss >> word; // [

    std::vector<std::string_view> temp_tokens;
    while (iss >> word && word != "]") {
        // Here word is local, storing a string_view to it causes dangling reference
        temp_tokens.push_back(std::string_view(word));
    }

    for (auto tv : temp_tokens) {
        entry.tokens.push_back(std::string(tv));
    }

    return entry;
}
EOF

    cat << 'EOF' > /home/user/proxy_analyzer/evaluator.cpp
#include <vector>
#include <string>

// Implement a stack-based postfix evaluator
double evaluate_postfix(const std::vector<std::string>& tokens) {
    // TODO: Implement this numerical algorithm
    return 0.0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
