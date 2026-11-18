#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    # Create app directory
    mkdir -p /app/bayesian_tracker-1.0.0/src

    # Create perturbed Cargo.toml
    cat << 'EOF' > /app/bayesian_tracker-1.0.0/Cargo.toml
[package]
name = "bayesian_tracker
version = "1.0.0"
edition = "2021"

[dependencies]
tiny_http = "0.12"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    # Create Rust source code
    cat << 'EOF' > /app/bayesian_tracker-1.0.0/src/main.rs
use tiny_http::{Server, Response, Method, Header};
use serde::{Deserialize, Serialize};
use std::env;
use std::sync::{Arc, Mutex};
use std::io::Read;

#[derive(Deserialize, Clone, Serialize)]
struct RecordReq {
    experiment_id: String,
    prior_mu: f64,
    prior_sigma: f64,
    likelihood_mu: f64,
    likelihood_sigma: f64,
}

#[derive(Serialize)]
struct RecordRes {
    posterior_mu: f64,
    posterior_sigma: f64,
}

fn main() {
    let secret = env::var("API_SECRET_KEY").expect("API_SECRET_KEY not set");
    let args: Vec<String> = env::args().collect();
    let addr = if args.len() > 1 { &args[1] } else { "127.0.0.1:9090" };

    let server = Server::http(addr).unwrap();
    let records: Arc<Mutex<Vec<RecordReq>>> = Arc::new(Mutex::new(Vec::new()));

    for mut request in server.incoming_requests() {
        let auth_header = request.headers().iter().find(|h| h.field.equiv("Authorization"));
        let valid_auth = match auth_header {
            Some(h) => {
                let val = String::from_utf8_lossy(h.value.as_ref());
                val == format!("Bearer {}", secret)
            },
            None => false,
        };

        if !valid_auth {
            let _ = request.respond(Response::from_string("Unauthorized").with_status_code(401));
            continue;
        }

        match (request.method(), request.url()) {
            (&Method::Post, "/record") => {
                let mut content = String::new();
                request.as_reader().read_to_string(&mut content).unwrap();
                if let Ok(req_data) = serde_json::from_str::<RecordReq>(&content) {
                    let prior_var = req_data.prior_sigma.powi(2);
                    let like_var = req_data.likelihood_sigma.powi(2);

                    let post_var = 1.0 / (1.0 / prior_var + 1.0 / like_var);
                    let post_mu = (req_data.prior_mu / prior_var + req_data.likelihood_mu / like_var) * post_var;
                    let post_sigma = post_var.sqrt();

                    records.lock().unwrap().push(req_data);

                    let res = RecordRes { posterior_mu: post_mu, posterior_sigma: post_sigma };
                    let res_str = serde_json::to_string(&res).unwrap();
                    let response = Response::from_string(res_str).with_header(Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap());
                    let _ = request.respond(response);
                } else {
                    let _ = request.respond(Response::from_string("Bad Request").with_status_code(400));
                }
            },
            (&Method::Get, "/aggregate") => {
                let data = records.lock().unwrap().clone();
                let res_str = serde_json::to_string(&data).unwrap();
                let response = Response::from_string(res_str).with_header(Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap());
                let _ = request.respond(response);
            },
            _ => {
                let _ = request.respond(Response::from_string("Not Found").with_status_code(404));
            }
        }
    }
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
