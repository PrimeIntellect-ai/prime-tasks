#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/nodes.csv
id,name
u1,Alice
u2,Bob
u3,Charlie
u4,Dave
u5,Eve
EOF

    cat << 'EOF' > /home/user/data/edges.csv
source,target
u1,u2
u1,u3
u2,u4
u3,u4
u4,u5
EOF

    mkdir -p /app/graph_engine_rs/src

    cat << 'EOF' > /app/graph_engine_rs/Cargo.toml
[package]
name = "graph_engine_rs"
version = "0.1.0"
edition = "2021"

[dependencies]
# PERTURBATION: serde and axum dependencies are commented out or missing features
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1", features = ["full"] }
axum = "0.6"
csv = "1.1"
EOF

    cat << 'EOF' > /app/graph_engine_rs/src/main.rs
use axum::{routing::get, Router, extract::{Query, State}};
use std::sync::Arc;
use std::net::SocketAddr;
use serde::{Deserialize, Serialize};

mod graph;

#[derive(Deserialize)]
struct PathParams { from: String, to: String }

#[derive(Deserialize)]
struct CentParams { node: String }

#[derive(Serialize)]
struct PathResponse { path: Vec<String> }

#[derive(Serialize)]
struct CentResponse { out_degree: usize }

async fn shortest_path(State(g): State<Arc<graph::Graph>>, Query(params): Query<PathParams>) -> axum::Json<PathResponse> {
    let path = g.shortest_path(&params.from, &params.to).unwrap_or_default();
    axum::Json(PathResponse { path })
}

async fn centrality(State(g): State<Arc<graph::Graph>>, Query(params): Query<CentParams>) -> axum::Json<CentResponse> {
    let out_degree = g.out_degree(&params.node);
    axum::Json(CentResponse { out_degree })
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 { return; }
    let g = Arc::new(graph::Graph::load(&args[1], &args[2]));

    let app = Router::new()
        .route("/shortest_path", get(shortest_path))
        .route("/centrality", get(centrality))
        .with_state(g);

    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

    cat << 'EOF' > /app/graph_engine_rs/src/graph.rs
use std::collections::{HashMap, VecDeque};

pub struct Graph {
    pub adj: HashMap<String, Vec<String>>,
}

#[derive(serde::Deserialize)]
struct NodeRecord { id: String }
#[derive(serde::Deserialize)]
struct EdgeRecord { source: String, target: String }

impl Graph {
    pub fn load(nodes_path: &str, edges_path: &str) -> Self {
        let mut rdr_n = csv::Reader::from_path(nodes_path).unwrap();
        let nodes: Vec<NodeRecord> = rdr_n.deserialize().map(|r| r.unwrap()).collect();

        let mut rdr_e = csv::Reader::from_path(edges_path).unwrap();
        let edges: Vec<EdgeRecord> = rdr_e.deserialize().map(|r| r.unwrap()).collect();

        let mut adj: HashMap<String, Vec<String>> = HashMap::new();

        // PERTURBATION: Implicit cross join leading to incorrect logic and bad performance.
        // The agent should rewrite this to:
        // for e in edges { adj.entry(e.source).or_default().push(e.target); }
        for n in &nodes {
            for e in &edges {
                adj.entry(n.id.clone()).or_default().push(e.target.clone());
            }
        }

        Self { adj }
    }

    pub fn out_degree(&self, node: &str) -> usize {
        self.adj.get(node).map(|v| v.len()).unwrap_or(0)
    }

    pub fn shortest_path(&self, start: &str, end: &str) -> Option<Vec<String>> {
        let mut q = VecDeque::new();
        let mut came_from: HashMap<String, String> = HashMap::new();

        q.push_back(start.to_string());
        came_from.insert(start.to_string(), start.to_string());

        while let Some(curr) = q.pop_front() {
            if curr == end {
                let mut path = vec![curr.clone()];
                let mut step = curr;
                while step != start {
                    step = came_from[&step].clone();
                    path.push(step.clone());
                }
                path.reverse();
                return Some(path);
            }

            if let Some(neighbors) = self.adj.get(&curr) {
                for nxt in neighbors {
                    if !came_from.contains_key(nxt) {
                        came_from.insert(nxt.clone(), curr.clone());
                        q.push_back(nxt.clone());
                    }
                }
            }
        }
        None
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
