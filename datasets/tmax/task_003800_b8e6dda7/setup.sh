#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc libssl-dev pkg-config
    pip3 install pytest

    mkdir -p /home/user/app/ingest
    mkdir -p /home/user/app/cleaner/src
    mkdir -p /home/user/app/serving/src

    # Create ingest data
    cat << 'EOF' > /home/user/app/ingest/data.json
{"raw": "Hello, World! Data Science 123."}
EOF

    # Create cleaner Cargo.toml
    cat << 'EOF' > /home/user/app/cleaner/Cargo.toml
[package]
name = "cleaner"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = { version = "0.11", features = ["json", "blocking"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tiny_http = "0.12"
EOF

    # Create cleaner main.rs
    cat << 'EOF' > /home/user/app/cleaner/src/main.rs
use std::io::Read;
use tiny_http::{Server, Response};
use serde_json::Value;

fn clean_and_tokenize(text: &str) -> Vec<String> {
    // TODO: implement
    vec![]
}

fn main() {
    let server = Server::http("0.0.0.0:8080").unwrap();
    for request in server.incoming_requests() {
        if request.url() == "/data" {
            let mut res = reqwest::blocking::get("http://localhost:8000/data.json").unwrap();
            let mut body = String::new();
            res.read_to_string(&mut body).unwrap();
            let json: Value = serde_json::from_str(&body).unwrap();
            let raw = json["raw"].as_str().unwrap();

            let tokens = clean_and_tokenize(raw);
            let response_body = serde_json::to_string(&tokens).unwrap();
            let response = Response::from_string(response_body).with_header(
                tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()
            );
            request.respond(response).unwrap();
        } else {
            request.respond(Response::from_string("Not Found").with_status_code(404)).unwrap();
        }
    }
}
EOF

    # Create serving Cargo.toml
    cat << 'EOF' > /home/user/app/serving/Cargo.toml
[package]
name = "serving"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = { version = "0.11", features = ["json", "blocking"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tiny_http = "0.12"
dotenv = "0.15"
EOF

    # Create serving main.rs
    cat << 'EOF' > /home/user/app/serving/src/main.rs
use std::io::Read;
use tiny_http::{Server, Response};
use serde_json::json;
use dotenv::dotenv;
use std::env;

fn main() {
    dotenv().ok();
    let server = Server::http("0.0.0.0:9000").unwrap();
    for request in server.incoming_requests() {
        if request.url() == "/predict" {
            let cleaner_url = env::var("CLEANER_URL").unwrap_or_default();
            let mut res = reqwest::blocking::get(&cleaner_url).unwrap();
            let mut body = String::new();
            res.read_to_string(&mut body).unwrap();

            let tokens: Vec<String> = serde_json::from_str(&body).unwrap();
            let score = (tokens.len() as f64) * 8.4;

            let response_body = json!({
                "status": "success",
                "score": score
            }).to_string();

            let response = Response::from_string(response_body).with_header(
                tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()
            );
            request.respond(response).unwrap();
        } else {
            request.respond(Response::from_string("Not Found").with_status_code(404)).unwrap();
        }
    }
}
EOF

    # Create serving .env (empty as per task, to be configured by agent)
    touch /home/user/app/serving/.env

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
