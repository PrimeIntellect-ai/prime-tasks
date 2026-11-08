#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cargo rustc
    pip3 install pytest

    mkdir -p /home/user/project/rust_sanitizer/src

    cat << 'EOF' > /home/user/project/deps.txt
waf_core: http_parser rust_sanitizer
http_parser: utils logger
rust_sanitizer: utils
logger: utils
utils: 
EOF

    cat << 'EOF' > /home/user/project/resolver.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <set>

using namespace std;

map<string, vector<string>> adj;
set<string> visited;
set<string> visiting;
vector<string> order;
bool cycle = false;

// TODO: Implement DFS or Kahn's for topological sort
void dfs(const string& node) {
    // YOUR CODE HERE
}

int main() {
    ifstream infile("/home/user/project/deps.txt");
    string line;
    set<string> all_nodes;

    while (getline(infile, line)) {
        if (line.empty()) continue;
        size_t colon = line.find(':');
        string target = line.substr(0, colon);
        all_nodes.insert(target);

        string deps_str = line.substr(colon + 1);
        stringstream ss(deps_str);
        string dep;
        while (ss >> dep) {
            adj[target].push_back(dep);
            all_nodes.insert(dep);
        }
    }

    // YOUR CODE HERE: Run the topological sort algorithm

    ofstream outfile("/home/user/project/build_order.txt");
    for (const string& node : order) {
        outfile << node << " ";
    }
    outfile << endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/rust_sanitizer/Cargo.toml
[package]
name = "rust_sanitizer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/project/rust_sanitizer/src/lib.rs
pub fn sanitize_html(input: &String) -> String {
    let mut s = input.clone();
    let ref_s = &s;
    s.push_str(" [sanitized]");
    println!("Processed from original: {}", ref_s);
    s
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
