#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/libcypher2sql-0.5.0/src
    mkdir -p /opt/oracle

    # Create the buggy source file
    cat << 'EOF' > /app/libcypher2sql-0.5.0/src/translator.cpp
#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <string_view>

struct Token {
    std::string type;
    std::string value;
};

std::vector<Token> parse(const std::string& input) {
    std::vector<Token> tokens;
    std::stringstream ss(input);
    std::string word;
    // Skip "MATCH"
    ss >> word;
    while (ss >> word) {
        auto colon = word.find(':');
        if (colon != std::string::npos) {
            tokens.push_back({word.substr(0, colon), word.substr(colon+1)});
        }
    }
    return tokens;
}

std::string build_sql(const std::vector<Token>& tokens) {
    std::string sql = "SELECT * FROM ";
    for(size_t i=0; i<tokens.size(); ++i) {
        if(tokens[i].type == "node") {
            sql += tokens[i].value + " n" + std::to_string(i/2);
        } else if (tokens[i].type == "edge") {
            sql += ", " + tokens[i].value + " e" + std::to_string(i/2) + ", ";
        }
    }
    sql += ";";
    return sql;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::string input = argv[1];
    auto tokens = parse(input);
    std::cout << build_sql(tokens) << std::endl;
    return 0;
}
EOF

    # Create the buggy Makefile
    cat << 'EOF' > /app/libcypher2sql-0.5.0/Makefile
CXX = g++
CXXFLAGS = -std=c++98

cypher2sql: src/translator.cpp
	$(CXX) $(CXXFLAGS) -o cypher2sql src/translator.cpp
EOF

    # Create the oracle source file
    cat << 'EOF' > /opt/oracle/translator_oracle.cpp
#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <string_view>

struct Token {
    std::string type;
    std::string value;
};

std::vector<Token> parse(const std::string& input) {
    std::vector<Token> tokens;
    std::stringstream ss(input);
    std::string word;
    ss >> word;
    while (ss >> word) {
        auto colon = word.find(':');
        if (colon != std::string::npos) {
            tokens.push_back({word.substr(0, colon), word.substr(colon+1)});
        }
    }
    return tokens;
}

std::string build_sql(const std::vector<Token>& tokens) {
    if (tokens.empty()) return "";
    std::string sql = "SELECT * FROM " + tokens[0].value + " n0";
    for(size_t i=1; i<tokens.size(); i+=2) {
        std::string edge = tokens[i].value;
        std::string next_node = tokens[i+1].value;
        int edge_idx = i/2;
        int prev_node_idx = edge_idx;
        int next_node_idx = edge_idx + 1;

        sql += " JOIN " + edge + " e" + std::to_string(edge_idx) + 
               " ON n" + std::to_string(prev_node_idx) + ".id=e" + std::to_string(edge_idx) + ".src" +
               " JOIN " + next_node + " n" + std::to_string(next_node_idx) + 
               " ON e" + std::to_string(edge_idx) + ".dst=n" + std::to_string(next_node_idx) + ".id";
    }
    sql += ";";
    return sql;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::string input = argv[1];
    auto tokens = parse(input);
    std::cout << build_sql(tokens) << std::endl;
    return 0;
}
EOF

    # Compile the oracle
    g++ -std=c++17 -o /opt/oracle/cypher2sql_oracle /opt/oracle/translator_oracle.cpp
    chmod +x /opt/oracle/cypher2sql_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
