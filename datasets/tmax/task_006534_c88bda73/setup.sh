#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc

pip3 install pytest scipy numpy matplotlib

mkdir -p /home/user/motif_scorer/src
mkdir -p /home/user/data

cat << 'EOF' > /home/user/motif_scorer/Cargo.toml
[package]
name = "motif_scorer"
version = "0.1.0"
edition = "2021"

[dependencies]
crossbeam = "0.8"
EOF

cat << 'EOF' > /home/user/motif_scorer/src/lib.rs
use std::sync::{Arc, Mutex};
use std::thread;

pub fn score_sequences(sequences: &[String], weights: [f64; 4]) -> f64 {
    let total_score = Arc::new(Mutex::new(0.0_f64));
    let mut handles = vec![];

    for seq in sequences {
        let seq = seq.clone();
        let score_ref = Arc::clone(&total_score);
        let handle = thread::spawn(move || {
            let mut seq_score = 0.0;
            for c in seq.chars() {
                match c {
                    'A' => seq_score += weights[0],
                    'C' => seq_score += weights[1],
                    'G' => seq_score += weights[2],
                    'T' => seq_score += weights[3],
                    _ => {}
                }
            }
            // Non-linear transformation to make it more sensitive to chunking/order
            let val = (seq_score + 1.0).ln();
            let mut s = score_ref.lock().unwrap();
            *s += val;
        });
        handles.push(handle);
    }

    for h in handles {
        h.join().unwrap();
    }

    let final_val = *total_score.lock().unwrap();
    final_val
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_determinism() {
        // Generate a large dummy sequence set to force race conditions
        let mut seqs = vec![];
        for i in 0..500 {
            let mut s = String::new();
            for j in 0..1000 {
                let c = match (i + j) % 4 {
                    0 => 'A',
                    1 => 'C',
                    2 => 'G',
                    _ => 'T',
                };
                s.push(c);
            }
            seqs.push(s);
        }

        let weights = [0.25, 0.25, 0.25, 0.25];
        let first_score = score_sequences(&seqs, weights);

        for _ in 0..10 {
            let score = score_sequences(&seqs, weights);
            assert_eq!(first_score, score, "Floating point reduction is not deterministic!");
        }
    }
}
EOF

cat << 'EOF' > /home/user/motif_scorer/src/main.rs
use motif_scorer::score_sequences;
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 6 {
        eprintln!("Usage: motif_scorer <fasta_file> <w_A> <w_C> <w_G> <w_T>");
        std::process::exit(1);
    }

    let fasta_path = &args[1];
    let w_a: f64 = args[2].parse().unwrap();
    let w_c: f64 = args[3].parse().unwrap();
    let w_g: f64 = args[4].parse().unwrap();
    let w_t: f64 = args[5].parse().unwrap();

    let content = fs::read_to_string(fasta_path).unwrap();
    let mut sequences = vec![];
    for line in content.lines() {
        if !line.starts_with('>') && !line.is_empty() {
            sequences.push(line.trim().to_string());
        }
    }

    let score = score_sequences(&sequences, [w_a, w_c, w_g, w_t]);
    println!("{}", score);
}
EOF

cat << 'EOF' > /home/user/data/promoters.fasta
>seq1
GGGCCCGGGCCCGGGCCC
>seq2
CCCGGGCCCGGGCCCGGG
>seq3
AGCTAGCTAGCTAGCTAG
>seq4
GGGGGGGGGGCCCCCCCC
>seq5
ATATATATATATATATAT
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
