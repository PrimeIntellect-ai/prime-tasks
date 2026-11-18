#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc binutils
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create C binary
    mkdir -p /app
    cat << 'EOF' > /app/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 205
#define MAX_NAME 20

char names[MAX_NODES][MAX_NAME];
int adj[MAX_NODES][MAX_NODES];
int in_degree[MAX_NODES];
int n, e;

int get_node_id(const char* name) {
    for (int i = 0; i < n; i++) {
        if (strcmp(names[i], name) == 0) return i;
    }
    return -1;
}

int main() {
    if (scanf("%d", &n) != 1) return 0;
    for (int i = 0; i < n; i++) {
        scanf("%19s", names[i]);
    }
    if (scanf("%d", &e) != 1) return 0;
    for (int i = 0; i < e; i++) {
        char u_name[MAX_NAME], v_name[MAX_NAME];
        scanf("%19s %19s", u_name, v_name);
        int u = get_node_id(u_name);
        int v = get_node_id(v_name);
        if (u != -1 && v != -1) {
            adj[u][v] = 1;
            in_degree[v]++;
        }
    }

    int visited = 0;
    int first = 1;
    while (visited < n) {
        int best = -1;
        for (int i = 0; i < n; i++) {
            if (in_degree[i] == 0) {
                if (best == -1 || strcmp(names[i], names[best]) < 0) {
                    best = i;
                }
            }
        }
        if (best == -1) break;
        in_degree[best] = -1;
        if (!first) printf(",");
        printf("%s", names[best]);
        first = 0;
        for (int i = 0; i < n; i++) {
            if (adj[best][i]) {
                in_degree[i]--;
            }
        }
        visited++;
    }
    printf("\n");
    return 0;
}
EOF
    gcc -O2 /app/legacy.c -o /app/legacy_graph_resolver
    strip /app/legacy_graph_resolver
    rm /app/legacy.c

    # Create Rust project
    mkdir -p /home/user/workspace/migration-service/src
    cat << 'EOF' > /home/user/workspace/migration-service/Cargo.toml
[package]
name = "migration-service"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/workspace/migration-service/src/main.rs
mod graph_parser;
mod schema_loader;

fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /home/user/workspace/migration-service/src/graph_parser.rs
pub struct Graph<'a> {
    pub nodes: Vec<&'a str>,
}

pub fn parse_graph(input: String) -> Graph<'static> {
    Graph { nodes: vec![&input] }
}
EOF

    cat << 'EOF' > /home/user/workspace/migration-service/src/schema_loader.rs
pub struct Schema<'a> {
    pub data: &'a str,
}

pub fn load_schema() -> &'static str {
    let local = String::from("schema");
    &local
}
EOF

    useradd -m -s /bin/bash user || true

    # Pre-fetch crates to speed up agent's work, ignore build errors
    cd /home/user/workspace/migration-service
    cargo fetch || true

    chmod -R 777 /home/user
