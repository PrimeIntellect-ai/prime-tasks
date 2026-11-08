#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        redis-server \
        cargo \
        rustc \
        curl

    pip3 install pytest redis requests numpy jupyterlab

    mkdir -p /app/telemetry_system/analyzer/src

    cat << 'EOF' > /app/telemetry_system/analyzer/Cargo.toml
[package]
name = "analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
redis = "0.23"
nalgebra = "0.32"
EOF

    cat << 'EOF' > /app/telemetry_system/analyzer/src/main.rs
use actix_web::{web, App, HttpServer, Responder, HttpResponse};
use serde::{Deserialize, Serialize};
use redis::Commands;

mod regression;

#[derive(Deserialize)]
struct PredictRequest {
    predict_timestamps: Vec<f64>,
}

#[derive(Serialize)]
struct PredictResponse {
    predictions: Vec<f64>,
}

async fn fit_and_predict(req: web::Json<PredictRequest>) -> impl Responder {
    let client = redis::Client::open("redis://127.0.0.1:6379").unwrap();
    let mut con = client.get_connection().unwrap();

    let stream_data: Vec<String> = con.lrange("telemetry_stream", 0, -1).unwrap_or_default();

    let mut x_train = Vec::new();
    let mut y_train = Vec::new();

    for item in stream_data {
        let parts: Vec<&str> = item.split(',').collect();
        if parts.len() == 2 {
            if let (Ok(x), Ok(y)) = (parts[0].parse::<f64>(), parts[1].parse::<f64>()) {
                x_train.push(x);
                y_train.push(y);
            }
        }
    }

    let coeffs = regression::fit_polynomial(&x_train, &y_train);
    let mut predictions = Vec::new();
    for &x in &req.predict_timestamps {
        predictions.push(regression::predict(x, &coeffs));
    }

    HttpResponse::Ok().json(PredictResponse { predictions })
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().route("/fit_and_predict", web::post().to(fit_and_predict))
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
EOF

    cat << 'EOF' > /app/telemetry_system/analyzer/src/regression.rs
use nalgebra::{DMatrix, DVector};

pub fn fit_polynomial(x: &[f64], y: &[f64]) -> Vec<f64> {
    let n = x.len();
    if n == 0 { return vec![0.0, 0.0, 0.0]; }

    // Degree 2 polynomial: y = c0 + c1*x + c2*x^2
    let mut x_matrix_data = Vec::with_capacity(n * 3);
    for &xi in x {
        x_matrix_data.push(1.0);
        x_matrix_data.push(xi);
        x_matrix_data.push(xi * xi);
    }

    let x_mat = DMatrix::from_row_slice(n, 3, &x_matrix_data);
    let y_vec = DVector::from_column_slice(y);

    let xt = x_mat.transpose();
    let xtx = &xt * &x_mat;
    let xty = &xt * &y_vec;

    // Naive inversion (ill-conditioned for large x)
    if let Some(xtx_inv) = xtx.try_inverse() {
        let beta = xtx_inv * xty;
        vec![beta[0], beta[1], beta[2]]
    } else {
        vec![0.0, 0.0, 0.0]
    }
}

pub fn predict(x: f64, coeffs: &[f64]) -> f64 {
    if coeffs.len() < 3 { return 0.0; }
    coeffs[0] + coeffs[1] * x + coeffs[2] * x * x
}
EOF

    # Pre-build the rust project to cache dependencies
    cd /app/telemetry_system/analyzer
    cargo build --release || true

    cat << 'EOF' > /app/telemetry_system/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup jupyter lab --no-browser --port=8888 --allow-root --ip=0.0.0.0 > /app/telemetry_system/jupyter.log 2>&1 &
EOF
    chmod +x /app/telemetry_system/start_services.sh

    cat << 'EOF' > /app/telemetry_system/evaluate.py
import redis, requests, numpy as np

r = redis.Redis(host='localhost', port=6379, db=0)
r.delete('telemetry_stream')

np.random.seed(42)
t_base = 1700000000
t = np.linspace(t_base, t_base + 1000, 100)
y = 2.5 * ((t - t_base)/1000)**2 + 1.2 * ((t - t_base)/1000) + 0.5 + np.random.normal(0, 0.01, 100)

for i in range(len(t)):
    r.rpush('telemetry_stream', f"{t[i]},{y[i]}")

try:
    resp = requests.post('http://localhost:8080/fit_and_predict', json={"predict_timestamps": t.tolist()})
    preds = resp.json()['predictions']
    mse = np.mean((y - np.array(preds))**2)
    print(f"FINAL_MSE={mse}")
except Exception as e:
    print(f"FINAL_MSE=999.0")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
