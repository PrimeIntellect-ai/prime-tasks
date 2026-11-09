#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/libdataset

    cat << 'EOF' > /app/libdataset/dataset.h
#ifndef DATASET_H
#define DATASET_H
#include <string>
#include <vector>

struct Paper {
    int id;
    int year;
    std::vector<int> cites;
};

std::vector<Paper> parse_dataset(const std::string& json_str);

#endif
EOF

    cat << 'EOF' > /app/libdataset/dataset.cpp
#include "dataset.h"
#include <regex>

std::vector<Paper> parse_dataset(const std::string& json_str) {
    std::vector<Paper> result;
    // A highly simplified regex-based parser for the specific fuzz format
    std::regex paper_regex(R"(\{"id":\s*(\d+),\s*"year":\s*(\d+),\s*"cites":\s*\[(.*?)\]\})");
    auto words_begin = std::sregex_iterator(json_str.begin(), json_str.end(), paper_regex);
    auto words_end = std::sregex_iterator();

    for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
        std::smatch match = *i;
        Paper p;
        p.id = std::stoi(match[1].str());
        p.year = std::stoi(match[2].str());

        std::string cites_str = match[3].str();
        std::regex cite_regex(R"(\d+)");
        auto c_begin = std::sregex_iterator(cites_str.begin(), cites_str.end(), cite_regex);
        for (std::sregex_iterator j = c_begin; j != words_end; ++j) {
            p.cites.push_back(std::stoi((*j).str()));
        }
        result.push_back(p);
    }
    return result;
}
EOF

    cat << 'EOF' > /app/libdataset/Makefile
CXX = g++
CXXFLAGS = -O2 -std=c++98

libdataset.a: dataset.o
	ar rcs libdataset.a dataset.o

dataset.o: dataset.cpp dataset.h
	$(CXX) $(CXXFLAGS) -c dataset.cpp -o dataset.o

clean:
	rm -f *.o *.a
EOF

    cat << 'EOF' > /app/oracle_graph_query
#!/usr/bin/env python3
import sys
import json

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    min_year = int(sys.argv[1])

    data = sys.stdin.read()
    try:
        j = json.loads(data)
    except:
        sys.exit(1)

    papers = j.get("papers", [])
    valid_papers = set()
    for p in papers:
        if p["year"] >= min_year:
            valid_papers.add(p["id"])

    edges = []
    for p in papers:
        if p["id"] in valid_papers:
            for c in p.get("cites", []):
                if c in valid_papers:
                    edges.append((p["id"], c))

    edges.sort()
    for u, v in edges:
        print(f"{u} -> {v}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_graph_query

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
