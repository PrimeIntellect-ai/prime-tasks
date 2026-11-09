#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make rustc cargo
    pip3 install pytest

    # Create libfastdir
    mkdir -p /app/libfastdir
    cat << 'EOF' > /app/libfastdir/fastdir.h
#ifndef FASTDIR_H
#define FASTDIR_H

typedef struct {
    char** files;
    int count;
} FileList;

FileList* extract_dependencies(const char* filepath);
void free_file_list(FileList* list);

#endif
EOF

    cat << 'EOF' > /app/libfastdir/fastdir.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fastdir.h"

FileList* extract_dependencies(const char* filepath) {
    FileList* list = malloc(sizeof(FileList));
    list->files = malloc(100 * sizeof(char*));
    list->count = 0;

    FILE* f = fopen(filepath, "r");
    if (!f) return list;

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char* start = strstr(line, "include \"");
        if (start) {
            start += 9;
            char* end = strchr(start, '"');
            if (end) {
                *end = '\0';
                list->files[list->count] = strdup(start);
                list->count++;
            }
        }
    }
    fclose(f);
    return list;
}

void free_file_list(FileList* list) {
    for (int i = 0; i < list->count; i++) {
        free(list->files[i]);
    }
    free(list->files);
    free(list);
}
EOF

    cat << 'EOF' > /app/libfastdir/Makefile
CC = gcc
CFLAGS = -Wall -Werror

all: libfastdir.a

libfastdir.a: fastdir.o
	ar rsc $@ $^

fastdir.o: fastdir.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o libfastdir.a
EOF

    # Create Rust project
    mkdir -p /home/user/analyzer/src
    cat << 'EOF' > /home/user/analyzer/Cargo.toml
[package]
name = "analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/analyzer/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/tmp/wrongdir");
    println!("cargo:rustc-link-lib=static=fastdir");
}
EOF

    cat << 'EOF' > /home/user/analyzer/src/main.rs
mod graph;
use graph::Graph;
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <dir>", args[0]);
        return;
    }

    let dir = &args[1];
    let mut g = Graph::new();

    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            if let Ok(ft) = entry.file_type() {
                if ft.is_file() {
                    let path = entry.path();
                    if let Some(ext) = path.extension() {
                        if ext == "txt" {
                            let filename = path.file_name().unwrap().to_str().unwrap().to_string();
                            g.add_node(filename.clone());

                            unsafe {
                                let c_path = std::ffi::CString::new(path.to_str().unwrap()).unwrap();
                                let list = extract_dependencies(c_path.as_ptr());
                                if !list.is_null() {
                                    let count = (*list).count;
                                    for i in 0..count {
                                        let dep_c = *((*list).files.offset(i as isize));
                                        let dep = std::ffi::CStr::from_ptr(dep_c).to_str().unwrap().to_string();
                                        g.add_edge(filename.clone(), dep);
                                    }
                                    free_file_list(list);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    let sorted = g.topo_sort();
    if sorted.is_empty() && g.nodes.len() > 0 {
        println!("CYCLE DETECTED");
    } else {
        for n in sorted {
            println!("{}", n);
        }
    }
}

#[repr(C)]
struct FileList {
    files: *mut *mut std::ffi::c_char,
    count: std::ffi::c_int,
}

extern "C" {
    fn extract_dependencies(filepath: *const std::ffi::c_char) -> *mut FileList;
    fn free_file_list(list: *mut FileList);
}
EOF

    cat << 'EOF' > /home/user/analyzer/src/graph.rs
use std::collections::{HashMap, HashSet};

pub struct Graph {
    pub nodes: HashSet<String>,
    pub edges: HashMap<String, Vec<String>>,
}

impl Graph {
    pub fn new() -> Self {
        Graph {
            nodes: HashSet::new(),
            edges: HashMap::new(),
        }
    }

    pub fn add_node(&mut self, node: String) {
        self.nodes.insert(node);
    }

    pub fn add_edge(&mut self, from: String, to: String) {
        self.nodes.insert(from.clone());
        self.nodes.insert(to.clone());
        self.edges.entry(from).or_insert_with(Vec::new).push(to);
    }

    pub fn topo_sort(&self) -> Vec<String> {
        let mut in_degree: HashMap<String, usize> = HashMap::new();
        for n in &self.nodes {
            in_degree.insert(n.clone(), 0);
        }

        for (_, neighbors) in &self.edges {
            for neighbor in neighbors {
                *in_degree.entry(neighbor.clone()).or_insert(0) += 1;
            }
        }

        let mut zero_in_degree = Vec::new();
        for (node, &deg) in &in_degree {
            if deg == 0 {
                zero_in_degree.push(node);
            }
        }

        let mut sorted = Vec::new();
        let mut count = 0;

        while let Some(u) = zero_in_degree.pop() {
            sorted.push(u.clone());
            count += 1;

            if let Some(neighbors) = self.edges.get(u) {
                for v in neighbors {
                    let deg = in_degree.get_mut(v).unwrap();
                    *deg -= 1;
                    if *deg == 0 {
                        zero_in_degree.push(v);
                    }
                }
            }
        }

        if count != self.nodes.len() {
            return Vec::new();
        }

        sorted
    }
}
EOF

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/analyzer_oracle
#!/usr/bin/env python3
import sys
import os
import re
import heapq

if len(sys.argv) < 2:
    sys.exit(1)

d = sys.argv[1]
nodes = set()
edges = {}

for root, _, files in os.walk(d):
    for f in files:
        if f.endswith('.txt'):
            nodes.add(f)
            path = os.path.join(root, f)
            with open(path, 'r') as file:
                for line in file:
                    m = re.search(r'include\s+"([^"]+)"', line)
                    if m:
                        dep = m.group(1)
                        nodes.add(dep)
                        edges.setdefault(f, []).append(dep)

in_degree = {n: 0 for n in nodes}
for u, neighbors in edges.items():
    for v in neighbors:
        in_degree[v] = in_degree.get(v, 0) + 1

zero_in = [n for n, d in in_degree.items() if d == 0]
heapq.heapify(zero_in)

sorted_nodes = []
while zero_in:
    u = heapq.heappop(zero_in)
    sorted_nodes.append(u)
    for v in edges.get(u, []):
        in_degree[v] -= 1
        if in_degree[v] == 0:
            heapq.heappush(zero_in, v)

if len(sorted_nodes) != len(nodes):
    print("CYCLE DETECTED")
else:
    for n in sorted_nodes:
        print(n)
EOF
    chmod +x /opt/oracle/analyzer_oracle

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
