#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo nginx curl
pip3 install pytest

mkdir -p /app/inference_service/src

cat << 'EOF' > /app/data_server.py
import http.server
import socketserver
import csv

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/data.csv':
            self.send_response(200)
            self.send_header('Content-type', 'text/csv')
            self.end_headers()
            self.wfile.write(b"x,y\n1.0,2.1\n2.0,3.9\n1.5,3.2\n3.0,6.0\n")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", 8000), Handler) as httpd:
    httpd.serve_forever()
EOF

cat << 'EOF' > /app/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 80;
        location /api/ {
            # BUG: proxies to port 8000 (data server) instead of 8080 (inference service)
            # and doesn't rewrite the path correctly.
            proxy_pass http://127.0.0.1:8000/;
        }
    }
}
EOF

cat << 'EOF' > /app/inference_service/Cargo.toml
[package]
name = "inference_service"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
reqwest = { version = "0.11" }
EOF

cat << 'EOF' > /app/inference_service/src/main.rs
use axum::{extract::Query, routing::get, Router, Json};
use serde::{Deserialize, Serialize};
use reqwest;
use std::sync::Arc;

#[derive(Deserialize)]
struct PredictQuery {
    x: f64,
}

#[derive(Serialize)]
struct PredictResponse {
    mean: f64,
    variance: f64,
}

struct Model {
    w_mean: f64,
    w_var: f64,
    noise_var: f64,
}

#[tokio::main]
async fn main() {
    let dataset = reqwest::get("http://127.0.0.1:8000/data.csv")
        .await.unwrap()
        .text().await.unwrap();

    let mut prior_var = 1.0_f64;
    let prior_mean = 0.0_f64;
    let noise_var = 2.0_f64;

    let mut sum_xx = 0.0;
    let mut sum_xy = 0.0;

    for line in dataset.lines().skip(1) {
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() == 2 {
            let x: f64 = parts[0].parse().unwrap();
            let y: f64 = parts[1].parse().unwrap();

            // BUG: sum_xx is accumulating x instead of x^2
            sum_xx += x / noise_var;
            sum_xy += (x * y) / noise_var;
        }
    }

    let post_var = 1.0 / ((1.0 / prior_var) + sum_xx);
    let post_mean = post_var * ((prior_mean / prior_var) + sum_xy);

    let model = Arc::new(Model {
        w_mean: post_mean,
        w_var: post_var,
        noise_var,
    });

    let app = Router::new().route("/predict", get({
        let model = Arc::clone(&model);
        move |query: Query<PredictQuery>| predict(query, Arc::clone(&model))
    }));

    axum::Server::bind(&"127.0.0.1:8080".parse().unwrap())
        .serve(app.into_make_service())
        .await
        .unwrap();
}

async fn predict(Query(q): Query<PredictQuery>, model: Arc<Model>) -> Json<PredictResponse> {
    let mean = model.w_mean * q.x;
    let variance = (q.x * q.x * model.w_var) + model.noise_var;
    Json(PredictResponse { mean, variance })
}
EOF

chmod -R 777 /app
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
