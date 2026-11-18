#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go g++ upx-ucl curl musl-tools
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="/opt/cargo/bin:$PATH"
    rustup target add x86_64-unknown-linux-musl

    # Create workspace directories
    mkdir -p /home/user/workspace/rust_graph/src
    mkdir -p /home/user/workspace/go_tester
    mkdir -p /app

    # Create Oracle C++ source
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <queue>
#include <sstream>
#include <algorithm>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 0;
    string s = argv[1];
    for (char& c : s) {
        if (c == ',' || c == '-' || c == '>') c = ' ';
    }
    stringstream ss(s);
    string u, v;
    map<string, vector<string>> adj;
    map<string, int> in_degree;
    vector<string> nodes;
    while (ss >> u >> v) {
        adj[u].push_back(v);
        in_degree[v]++;
        if (in_degree.find(u) == in_degree.end()) in_degree[u] = 0;
        nodes.push_back(u); nodes.push_back(v);
    }
    sort(nodes.begin(), nodes.end());
    nodes.erase(unique(nodes.begin(), nodes.end()), nodes.end());

    priority_queue<string, vector<string>, greater<string>> q;
    for (auto& n : nodes) {
        if (in_degree[n] == 0) q.push(n);
    }

    vector<string> res;
    while (!q.empty()) {
        string curr = q.top(); q.pop();
        res.push_back(curr);
        for (auto& nxt : adj[curr]) {
            if (--in_degree[nxt] == 0) q.push(nxt);
        }
    }

    if (res.size() != nodes.size() && !nodes.empty()) {
        cout << "CYCLE_DETECTED" << endl;
    } else {
        for (int i = 0; i < res.size(); ++i) {
            cout << res[i] << (i == res.size()-1 ? "" : ",");
        }
        cout << endl;
    }
    return 0;
}
EOF

    # Compile, strip, and UPX the oracle
    g++ -O3 /tmp/oracle.cpp -o /app/oracle_graph_solver
    strip --strip-all /app/oracle_graph_solver
    upx /app/oracle_graph_solver

    # Scaffold Rust project
    cat << 'EOF' > /home/user/workspace/rust_graph/Cargo.toml
[package]
name = "rust_graph"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/workspace/rust_graph/src/main.rs
mod resolver;

fn main() {
    resolver::resolve();
}
EOF

    cat << 'EOF' > /home/user/workspace/rust_graph/src/resolver.rs
pub fn resolve() {
    let mut x = String::from("hello");
    let y = &mut x;
    let z = &mut x; // Intentional borrow checker error
    println!("{}{}", y, z);
}
EOF

    # Scaffold Go project
    cat << 'EOF' > /home/user/workspace/go_tester/go.mod
module gotester

go 1.18
EOF

    cat << 'EOF' > /home/user/workspace/go_tester/bench_test.go
package gotester

import "testing"

func BenchmarkGraphSolver(b *testing.B) {
    // Implement property testing and benchmarking here
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true

    # Ensure environment variables are available for all users
    echo 'export RUSTUP_HOME=/opt/rust' >> /etc/profile.d/rust.sh
    echo 'export CARGO_HOME=/opt/cargo' >> /etc/profile.d/rust.sh
    echo 'export PATH="/opt/cargo/bin:$PATH"' >> /etc/profile.d/rust.sh

    chmod -R 777 /home/user
    chmod -R 777 /opt/rust /opt/cargo
