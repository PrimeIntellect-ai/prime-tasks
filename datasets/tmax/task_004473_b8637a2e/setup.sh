#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifact_server/src
    cd /home/user/artifact_server

    cat << 'EOF' > Cargo.toml
[package]
name = "artifact_server"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};

// A simple custom data structure for artifact storage
struct ArtifactStore {
    // BUG: This stores references, which will violate lifetimes when parsed from the transient TCP buffer.
    // The agent must change this to HashMap<String, String> or similar.
    cache: HashMap<&'static str, String>, 
}

impl ArtifactStore {
    fn new() -> Self {
        ArtifactStore {
            cache: HashMap::new(),
        }
    }

    fn insert(&mut self, id: &str, data: String) {
        // BUG: The agent needs to fix the cache to take owned Strings, e.g., self.cache.insert(id.to_string(), data);
        self.cache.insert(id, data); 
    }

    fn get(&self, id: &str) -> Option<&String> {
        self.cache.get(id)
    }
}

fn handle_client(mut stream: TcpStream, store: &mut ArtifactStore) {
    let mut buffer = [0; 512];
    if stream.read(&mut buffer).is_ok() {
        let request = String::from_utf8_lossy(&buffer);

        // Simple URL routing and parameter parsing
        if request.starts_with("GET /artifact/") {
            // Extract the id parameter
            if let Some(id_start) = request.find("?id=") {
                let id_part = &request[id_start + 4..];
                let id = id_part.split_whitespace().next().unwrap_or("");

                let response_body = match store.get(id) {
                    Some(data) => data.clone(),
                    None => {
                        let new_data = format!("ArtifactData_{}", id);
                        store.insert(id, new_data.clone());
                        new_data
                    }
                };

                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}",
                    response_body.len(),
                    response_body
                );
                stream.write_all(response.as_bytes()).unwrap();
                return;
            }
        }

        let response = "HTTP/1.1 400 Bad Request\r\n\r\n";
        stream.write_all(response.as_bytes()).unwrap();
    }
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    let mut store = ArtifactStore::new();

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                handle_client(stream, &mut store);
            }
            Err(_) => {}
        }
    }
}
EOF

    chown -R user:user /home/user/artifact_server
    chmod -R 777 /home/user
