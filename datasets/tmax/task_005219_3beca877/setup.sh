#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import math
with open("/home/user/dataset.csv", "w") as f:
    for i in range(100):
        x = i * 0.1
        # true a=2.0, b=3.0
        # y = 2.0 * sin(x) + 3.0 * (1 - cos(x))
        y = 2.0 * math.sin(x) + 3.0 * (1.0 - math.cos(x))
        f.write(f"{x},{y}\n")
EOF
    python3 /home/user/generate_data.py

    cd /home/user
    cargo new model_fitter
    cat << 'EOF' > /home/user/model_fitter/Cargo.toml
[package]
name = "model_fitter"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/model_fitter/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::sync::{Arc, Mutex};
use std::thread;

fn model_predict(x: f64, a: f64, b: f64) -> f64 {
    let steps = 100;
    let dt = x / (steps as f64);
    let mut sum = 0.0;
    for i in 0..steps {
        let t = (i as f64) * dt;
        sum += (a * t.cos() + b * t.sin()) * dt;
    }
    sum
}

fn main() {
    let file = File::open("/home/user/dataset.csv").unwrap();
    let reader = BufReader::new(file);
    let mut data = Vec::new();
    for line in reader.lines() {
        let line = line.unwrap();
        let parts: Vec<&str> = line.split(',').collect();
        let x: f64 = parts[0].parse().unwrap();
        let y: f64 = parts[1].parse().unwrap();
        data.push((x, y));
    }

    let mut a = 0.5;
    let mut b = 0.5;
    let learning_rate = 0.01;

    for epoch in 0..500 {
        let grad_a = Arc::new(Mutex::new(0.0));
        let grad_b = Arc::new(Mutex::new(0.0));

        let mut handles = vec![];

        for chunk in data.chunks(10) {
            let chunk = chunk.to_vec();
            let ga = Arc::clone(&grad_a);
            let gb = Arc::clone(&grad_b);
            let a_val = a;
            let b_val = b;

            handles.push(thread::spawn(move || {
                for (x, y) in chunk {
                    let pred = model_predict(x, a_val, b_val);
                    let err = pred - y;

                    // Numerical derivative of prediction wrt a and b
                    let pred_da = model_predict(x, a_val + 0.0001, b_val);
                    let da = (pred_da - pred) / 0.0001;

                    let pred_db = model_predict(x, a_val, b_val + 0.0001);
                    let db = (pred_db - pred) / 0.0001;

                    *ga.lock().unwrap() += err * da;
                    *gb.lock().unwrap() += err * db;
                }
            }));
        }

        for h in handles {
            h.join().unwrap();
        }

        let final_ga = *grad_a.lock().unwrap() / (data.len() as f64);
        let final_gb = *grad_b.lock().unwrap() / (data.len() as f64);

        a -= learning_rate * final_ga;
        b -= learning_rate * final_gb;
    }

    println!("Final params: a={:.2}, b={:.2}", a, b);
}
EOF

    chmod -R 777 /home/user
