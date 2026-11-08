#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential nlohmann-json3-dev
pip3 install pytest

# Create directories
mkdir -p /app/libgraphbackup-1.2.0
mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

# Create graphbackup.h
cat << 'EOF' > /app/libgraphbackup-1.2.0/graphbackup.h
#ifndef GRAPHBACKUP_H
#define GRAPHBACKUP_H
#include <vector>
#include <string>

std::vector<std::string> extract_queries(const std::string& filepath);

#endif
EOF

# Create graphbackup.cpp
cat << 'EOF' > /app/libgraphbackup-1.2.0/graphbackup.cpp
#include "graphbackup.h"
#include <fstream>
#include <sstream>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

std::vector<std::string> extract_queries(const std::string& filepath) {
    std::vector<std::string> queries;
    std::ifstream file(filepath);
    if (!file.is_open()) return queries;

    json j;
    try {
        file >> j;
        if (j.contains("queries") && j["queries"].is_array()) {
            for (const auto& q : j["queries"]) {
                queries.push_back(q.get<std::string>());
            }
        }
    } catch (...) {}

    return queries;
}
EOF

# Create broken Makefile
cat << 'EOF' > /app/libgraphbackup-1.2.0/Makefile
CXX = gcc
CXXFLAGS = -fPIC -I.
LDFLAGS = 

all: libgraphbackup.so

libgraphbackup.so: graphbackup.o
	$(CXX) $(LDFLAGS) -o $@ $^

graphbackup.o: graphbackup.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

install:
	mkdir -p build/lib build/include
	cp libgraphbackup.so build/lib/
	cp graphbackup.h build/include/
EOF

# Generate corpora
python3 -c "
import json
import os

clean_queries = [
    'MATCH (n) RETURN n',
    'CREATE (n:Person {name: \"Alice\"})',
    'MERGE (n:Person {name: \"Bob\"})',
    'MATCH (n:Person) SET n.age = 30 RETURN n'
]

evil_queries = [
    'MATCH (n) DETACH DELETE n',
    'DROP INDEX ON :Person(name)',
    'MATCH (n) REMOVE n.age',
    'CALL dbms.security.createUser(\"admin\", \"password\", false)'
]

for i in range(50):
    with open(f'/app/corpora/clean/backup_{i}.json', 'w') as f:
        json.dump({'queries': [clean_queries[i % len(clean_queries)]]}, f)

for i in range(50):
    with open(f'/app/corpora/evil/backup_{i}.json', 'w') as f:
        json.dump({'queries': [clean_queries[i % len(clean_queries)], evil_queries[i % len(evil_queries)]]}, f)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
