#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/csv_parser/include
    mkdir -p /home/user/src
    mkdir -p /opt/oracle

    # Create vendored package files
    cat << 'EOF' > /app/vendored/csv_parser/include/csv.h
#ifndef CSV_H
#define CSV_H
#include <string>
// Deliberately missing #include <vector>
class CSVParser {
public:
    std::vector<std::string> parse(const std::string& line);
};
#endif
EOF

    cat << 'EOF' > /app/vendored/csv_parser/csv.cpp
#include "include/csv.h"
#include <sstream>
#include <vector>

std::vector<std::string> CSVParser::parse(const std::string& line) {
    std::vector<std::string> result;
    std::stringstream ss(line);
    std::string item;
    while (std::getline(ss, item, ',')) {
        result.push_back(item);
    }
    return result;
}
EOF

    cat << 'EOF' > /app/vendored/csv_parser/Makefile
CXX = g++
CXXFLAGS = -Iinclude -std=c++11

all: libcsvparser.a

libcsvparser.a: csv.o
	ar rcs libcsvparser.a csv.o

csv.o: csv.cpp
# Deliberately missing tab on the next line
$(CXX) $(CXXFLAGS) -c csv.cpp -o csv.o

clean:
	rm -f *.o *.a
EOF

    # Create skeleton file
    cat << 'EOF' > /home/user/src/manifest_filter.cpp
#include <iostream>
#include <string>

int main() {
    // TODO: Implement manifest filtering logic
    return 0;
}
EOF

    # Create and compile oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>

int main() {
    std::string line;
    std::vector<std::string> results;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string filename, size_str, file_type;
        if (std::getline(ss, filename, ',') &&
            std::getline(ss, size_str, ',') &&
            std::getline(ss, file_type, ',')) {

            if (!file_type.empty() && file_type.back() == '\r') {
                file_type.pop_back();
            }

            try {
                long long size = std::stoll(size_str);
                if (file_type == "log" && size > 10485760) {
                    results.push_back(filename);
                }
            } catch (...) {
                // ignore
            }
        }
    }

    std::cout << "[\n";
    for (size_t i = 0; i < results.size(); ++i) {
        std::cout << "  \"" << results[i] << "\"";
        if (i < results.size() - 1) {
            std::cout << ",";
        }
        std::cout << "\n";
    }
    std::cout << "]\n";
    return 0;
}
EOF

    g++ -O3 -std=c++11 /opt/oracle/oracle.cpp -o /opt/oracle/manifest_filter_oracle
    rm /opt/oracle/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
