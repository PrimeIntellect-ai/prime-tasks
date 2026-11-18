#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/anomaly_detector/src
    cd /home/user/anomaly_detector

    cat << 'EOF' > Cargo.toml
[package]
name = "anomaly_detector"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let file = File::open("/home/user/data.csv").expect("Failed to open data.csv");
    let reader = BufReader::new(file);

    let mut data_x: HashMap<i32, Vec<f64>> = HashMap::new();
    let mut data_y: HashMap<i32, Vec<f64>> = HashMap::new();

    for line in reader.lines().skip(1) {
        let line = line.unwrap();
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() == 3 {
            // BUG: Parses id as f64 to handle "NaN", then casts to i32. 
            // f64::NAN as i32 is 0.
            let id_f = parts[0].parse::<f64>().unwrap();
            let id = id_f as i32;
            let ts = parts[1].parse::<f64>().unwrap();
            let val = parts[2].parse::<f64>().unwrap();

            data_x.entry(id).or_insert(Vec::new()).push(ts);
            data_y.entry(id).or_insert(Vec::new()).push(val);
        }
    }

    let mut ids: Vec<&i32> = data_x.keys().collect();
    ids.sort();

    for id in ids {
        let xs = &data_x[id];
        let ys = &data_y[id];
        let n = xs.len() as f64;
        let sum_x: f64 = xs.iter().sum();
        let sum_y: f64 = ys.iter().sum();
        let sum_xy: f64 = xs.iter().zip(ys.iter()).map(|(x, y)| x * y).sum();
        let sum_xx: f64 = xs.iter().map(|x| x * x).sum();

        let slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x);
        println!("{}: {}", id, slope);
    }
}
EOF

    cat << 'EOF' > /home/user/data.csv
id,timestamp,value
0,1,2.0
0,2,4.0
0,3,6.0
0,4,8.0
1,1,3.5
1,2,7.0
1,3,10.5
1,4,14.0
NaN,1,100.0
NaN,2,0.0
NaN,3,-100.0
NaN,4,-200.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/anomaly_detector
    chown user:user /home/user/data.csv
    chmod -R 777 /home/user
