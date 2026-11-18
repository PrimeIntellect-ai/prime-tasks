#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget imagemagick curl
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the filter rule image
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'Only include papers where year >= 2021'" /app/filter_rule.png

    # Create dataset.csv
    cat << 'EOF' > /home/user/dataset.csv
AuthorID,AuthorName,PaperID,PaperYear
1,Alice,101,2020
1,Alice,102,2022
2,Bob,101,2020
3,Charlie,102,2022
4,David,103,2022
EOF

    # Create graph_server.cpp
    cat << 'EOF' > /home/user/graph_server.cpp
#include "httplib.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <set>

struct Record { int author_id; std::string name; int paper_id; int year; };
std::vector<Record> dataset;

void load_data() {
    std::ifstream file("dataset.csv");
    std::string line, token;
    std::getline(file, line); // skip header
    while(std::getline(file, line)) {
        std::stringstream ss(line);
        Record r;
        std::getline(ss, token, ','); r.author_id = std::stoi(token);
        std::getline(ss, r.name, ',');
        std::getline(ss, token, ','); r.paper_id = std::stoi(token);
        std::getline(ss, token, ','); r.year = std::stoi(token);
        dataset.push_back(r);
    }
}

std::string get_coauthors(const std::string& author_name) {
    std::set<std::string> coauthors;
    // BUG: Cartesian product cross-join
    for (const auto& r1 : dataset) {
        if (r1.name == author_name) {
            for (const auto& r2 : dataset) {
                // Missing condition: if (r1.paper_id == r2.paper_id)
                // Missing filter: r1.year >= 2021
                if (r2.name != author_name) {
                    coauthors.insert(r2.name);
                }
            }
        }
    }
    std::string res = "{\"author\": \"" + author_name + "\", \"coauthors\": [";
    int i = 0;
    for (const auto& c : coauthors) {
        res += "\"" + c + "\"";
        if (++i < coauthors.size()) res += ", ";
    }
    res += "]}";
    return res;
}

int main() {
    load_data();
    httplib::Server svr;
    svr.Get("/coauthors", [](const httplib::Request& req, httplib::Response& res) {
        if (req.has_param("name")) {
            auto name = req.get_param_value("name");
            res.set_content(get_coauthors(name), "application/json");
        } else {
            res.status = 400;
        }
    });
    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    # Download httplib.h
    wget -qO /home/user/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
