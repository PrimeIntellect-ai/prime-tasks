#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc redis-server
    pip3 install pytest

    mkdir -p /app/data_service/src

    cat << 'EOF' > /app/data_service/Cargo.toml
[package]
name = "data_service"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
rand = "0.8"
redis = "0.23"
EOF

    cat << 'EOF' > /app/data_service/src/main.rs
use actix_web::{web, App, HttpServer, Responder, HttpResponse};
use serde::{Deserialize, Serialize};
use rand::Rng;

#[derive(Deserialize)]
struct InputData(Vec<Vec<f64>>);

#[derive(Serialize)]
struct OutputData {
    original: Vec<Vec<f64>>,
    bootstraps: Vec<Vec<Vec<f64>>>,
}

async fn prepare(data: web::Json<Vec<Vec<f64>>>) -> impl Responder {
    let input = data.into_inner();
    let num_rows = input.len();
    if num_rows == 0 {
        return HttpResponse::Ok().json(OutputData { original: vec![], bootstraps: vec![] });
    }
    let num_cols = input[0].len();

    let mut rng = rand::thread_rng();
    let mut bootstraps = Vec::new();
    for _ in 0..5 {
        let mut sample = Vec::new();
        for _ in 0..num_rows {
            let idx = rng.gen_range(0..num_rows);
            sample.push(input[idx].clone());
        }
        bootstraps.push(sample);
    }

    // Data leak: combining original and bootstraps to calculate stats
    let mut combined = input.clone();
    for b in &bootstraps {
        combined.extend(b.clone());
    }

    let mut means = vec![0.0; num_cols];
    for row in &combined {
        for j in 0..num_cols {
            means[j] += row[j];
        }
    }
    for j in 0..num_cols {
        means[j] /= combined.len() as f64;
    }

    let mut std_devs = vec![0.0; num_cols];
    for row in &combined {
        for j in 0..num_cols {
            std_devs[j] += (row[j] - means[j]).powi(2);
        }
    }
    for j in 0..num_cols {
        std_devs[j] = (std_devs[j] / combined.len() as f64).sqrt();
        if std_devs[j] == 0.0 {
            std_devs[j] = 1.0;
        }
    }

    let scale = |dataset: &Vec<Vec<f64>>| -> Vec<Vec<f64>> {
        let mut scaled = dataset.clone();
        for i in 0..scaled.len() {
            for j in 0..num_cols {
                scaled[i][j] = (scaled[i][j] - means[j]) / std_devs[j];
            }
        }
        scaled
    };

    let scaled_original = scale(&input);
    let mut scaled_bootstraps = Vec::new();
    for b in &bootstraps {
        scaled_bootstraps.push(scale(b));
    }

    HttpResponse::Ok().json(OutputData {
        original: scaled_original,
        bootstraps: scaled_bootstraps,
    })
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().route("/prepare", web::post().to(prepare))
    })
    .bind(("127.0.0.1", 3000))?
    .run()
    .await
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
