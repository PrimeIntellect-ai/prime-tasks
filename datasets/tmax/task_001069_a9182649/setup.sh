#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc binutils
    pip3 install pytest hypothesis

    mkdir -p /app
    cat << 'EOF' > /tmp/main.rs
use std::io::{self, BufRead};
use std::collections::{HashMap, HashSet};

fn main() {
    let stdin = io::stdin();
    let mut nodes: HashMap<String, i32> = HashMap::new();
    let mut edges: Vec<(String, String)> = Vec::new();

    for line in stdin.lock().lines() {
        let l = line.unwrap();
        let trimmed = l.trim();
        if trimmed.is_empty() { continue; }
        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        if parts[0] == "V" {
            if parts.len() != 3 { println!("Error: MALFORMED_INPUT"); return; }
            if let Ok(lat) = parts[2].parse::<i32>() {
                if lat <= 0 { println!("Error: MALFORMED_INPUT"); return; }
                nodes.insert(parts[1].to_string(), lat);
            } else {
                println!("Error: MALFORMED_INPUT"); return;
            }
        } else if parts[0] == "E" {
            if parts.len() != 3 { println!("Error: MALFORMED_INPUT"); return; }
            edges.push((parts[1].to_string(), parts[2].to_string()));
        } else {
            println!("Error: MALFORMED_INPUT"); return;
        }
    }

    for (u, v) in &edges {
        if !nodes.contains_key(u) || !nodes.contains_key(v) {
            println!("Error: UNDECLARED_NODE"); return;
        }
    }

    if nodes.is_empty() {
        println!("Critical Path: NONE | Total Latency: 0");
        return;
    }

    // Cycle detection & Topo sort
    let mut in_degree: HashMap<String, usize> = HashMap::new();
    let mut adj: HashMap<String, Vec<String>> = HashMap::new();
    for k in nodes.keys() {
        in_degree.insert(k.clone(), 0);
        adj.insert(k.clone(), Vec::new());
    }
    for (u, v) in &edges {
        adj.get_mut(u).unwrap().push(v.clone());
        *in_degree.get_mut(v).unwrap() += 1;
    }

    let mut queue: Vec<String> = Vec::new();
    for (k, v) in &in_degree {
        if *v == 0 { queue.push(k.clone()); }
    }

    let mut topo_order = Vec::new();
    let mut head = 0;
    while head < queue.len() {
        let u = queue[head].clone();
        head += 1;
        topo_order.push(u.clone());
        for v in &adj[&u] {
            let deg = in_degree.get_mut(v).unwrap();
            *deg -= 1;
            if *deg == 0 { queue.push(v.clone()); }
        }
    }

    if topo_order.len() != nodes.len() {
        println!("Error: CYCLE_DETECTED"); return;
    }

    // DP for longest path
    let mut dist: HashMap<String, i32> = HashMap::new();
    let mut path: HashMap<String, Vec<String>> = HashMap::new();
    for u in &topo_order {
        dist.insert(u.clone(), *nodes.get(u).unwrap());
        path.insert(u.clone(), vec![u.clone()]);
    }

    for u in &topo_order {
        let d_u = *dist.get(u).unwrap();
        let p_u = path.get(u).unwrap().clone();
        for v in &adj[u] {
            let cand_dist = d_u + nodes.get(v).unwrap();
            let mut cand_path = p_u.clone();
            cand_path.push(v.clone());

            let curr_dist = *dist.get(v).unwrap();
            let curr_path = path.get(v).unwrap().clone();

            if cand_dist > curr_dist || (cand_dist == curr_dist && cand_path.join("") < curr_path.join("")) {
                dist.insert(v.clone(), cand_dist);
                path.insert(v.clone(), cand_path);
            }
        }
    }

    let mut max_d = -1;
    let mut best_p: Vec<String> = Vec::new();
    for (u, d) in &dist {
        let p = path.get(u).unwrap();
        if *d > max_d || (*d == max_d && p.join("") < best_p.join("")) {
            max_d = *d;
            best_p = p.clone();
        }
    }

    println!("Critical Path: {} | Total Latency: {}", best_p.join(" -> "), max_d);
}
EOF

    rustc -O /tmp/main.rs -o /app/graph_oracle
    strip /app/graph_oracle
    rm /tmp/main.rs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
