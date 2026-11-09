#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/seq_analyzer/src
    mkdir -p /home/user/seq_analyzer/data

    cat << 'EOF' > /home/user/seq_analyzer/Cargo.toml
[package]
name = "seq_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/seq_analyzer/src/main.rs
use std::env;
use std::fs;
use std::f64::consts::PI;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: seq_analyzer <seq1> <seq2>");
        std::process::exit(1);
    }

    let seq1 = fs::read_to_string(&args[1]).expect("Failed to read seq1").trim().to_string();
    let seq2 = fs::read_to_string(&args[2]).expect("Failed to read seq2").trim().to_string();

    let dist1 = compute_spectral_profile(&seq1);
    let dist2 = compute_spectral_profile(&seq2);

    let kl_div = kullback_leibler_divergence(&dist1, &dist2);
    println!("{:.6}", kl_div);
}

fn compute_spectral_profile(seq: &str) -> Vec<f64> {
    let bytes = seq.as_bytes();
    let mut profile = vec![0.0; 10]; // 10 frequency bins

    let mut pos = 0;
    let window_size = 10;
    let mut step = 4;

    while pos + window_size <= bytes.len() {
        let window = &bytes[pos..pos + window_size];

        // Count 'A's to estimate local complexity (dummy metric)
        let a_count = window.iter().filter(|&&b| b == b'A').count();

        if a_count > 5 {
            // BUG: step size can become 0, causing infinite loop
            step /= 2; 
        } else if a_count < 2 {
            step += 1;
        }

        // Compute dummy DFT power spectrum for the window
        for k in 0..10 {
            let mut re = 0.0;
            let mut im = 0.0;
            for n in 0..window_size {
                let val = match window[n] {
                    b'A' => 1.0, b'C' => 2.0, b'G' => 3.0, b'T' => 4.0, _ => 0.0,
                };
                let angle = -2.0 * PI * (k as f64) * (n as f64) / (window_size as f64);
                re += val * angle.cos();
                im += val * angle.sin();
            }
            profile[k] += re * re + im * im;
        }

        pos += step;
    }

    // Normalize to create a probability distribution
    let sum: f64 = profile.iter().sum();
    if sum > 0.0 {
        for p in profile.iter_mut() {
            *p /= sum;
        }
    } else {
        for p in profile.iter_mut() {
            *p = 0.1;
        }
    }

    profile
}

fn kullback_leibler_divergence(p: &[f64], q: &[f64]) -> f64 {
    p.iter().zip(q.iter())
        .map(|(&p_i, &q_i)| {
            if p_i > 0.0 && q_i > 0.0 {
                p_i * (p_i / q_i).ln()
            } else {
                0.0
            }
        })
        .sum()
}
EOF

    cat << 'EOF' > /home/user/seq_analyzer/data/seqA.txt
ATCGATCGAAAAAATCGATCGATCG
EOF

    cat << 'EOF' > /home/user/seq_analyzer/data/seqB.txt
GCTAGCTAGCTAAAAAAGCTAGCTA
EOF

    cat << 'EOF' > /home/user/seq_analyzer/regression_test.sh
#!/bin/bash
cargo build --quiet
timeout 2s cargo run --quiet data/seqA.txt data/seqB.txt > out.tmp
if [ $? -eq 124 ]; then
    echo "FAIL: Program timed out (diverged)."
    rm out.tmp
    exit 1
fi
echo "PASS: Program completed."
rm out.tmp
exit 0
EOF

    chmod +x /home/user/seq_analyzer/regression_test.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
