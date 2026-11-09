#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/vendored/libcsv_etl
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/vendored/libcsv_etl/Makefile
CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -DSIMULATE_RETRY_DUPLICATION=1

all: libcsv_etl.a

csv_etl.o: csv_etl.cpp csv_etl.h
	$(CXX) $(CXXFLAGS) -c csv_etl.cpp -o csv_etl.o

libcsv_etl.a: csv_etl.o
	ar rcs libcsv_etl.a csv_etl.o

clean:
	rm -f *.o *.a
EOF

    cat << 'EOF' > /app/vendored/libcsv_etl/csv_etl.h
#pragma once
#include <string>
#include <vector>

namespace csv_etl {
    std::vector<std::string> split(const std::string& line);
}
EOF

    cat << 'EOF' > /app/vendored/libcsv_etl/csv_etl.cpp
#include "csv_etl.h"
#include <sstream>

namespace csv_etl {
    std::vector<std::string> split(const std::string& line) {
        std::vector<std::string> result;
        std::stringstream ss(line);
        std::string item;
        while (std::getline(ss, item, ',')) {
            result.push_back(item);
        }
        return result;
    }
}
EOF

    touch /app/corpora/clean/clean1.csv
    touch /app/corpora/clean/clean2.csv
    touch /app/corpora/evil/evil_dupes.csv
    touch /app/corpora/evil/evil_anomalies.csv
    touch /app/corpora/evil/evil_unmasked.csv
    touch /app/corpora/evil/evil_bad_status.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
