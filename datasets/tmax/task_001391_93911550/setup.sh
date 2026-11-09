#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create papers.json
    cat << 'EOF' > /home/user/papers.json
[
  {"id": "doc1", "text": "deep learning for computer vision"},
  {"id": "doc2", "text": "natural language processing with deep learning"},
  {"id": "doc3", "text": "computer vision applications in robotics"},
  {"id": "doc4", "text": "robotics and control systems"},
  {"id": "doc5", "text": "natural language processing and text mining"}
]
EOF

    # Create Rust project
    cd /home/user
    cargo new paper_recommender

    # Update Cargo.toml
    cat << 'EOF' > /home/user/paper_recommender/Cargo.toml
[package]
name = "paper_recommender"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    # Create main.rs
    cat << 'EOF' > /home/user/paper_recommender/src/main.rs
use std::collections::{HashMap, HashSet};
use std::fs;
use serde::Deserialize;

#[derive(Deserialize, Debug)]
struct Paper {
    id: String,
    text: String,
}

fn main() {
    let data = fs::read_to_string("/home/user/papers.json").expect("Unable to read file");
    let papers: Vec<Paper> = serde_json::from_str(&data).expect("JSON parsing failed");

    let mut vocab = HashSet::new();
    let mut doc_tokens = Vec::new();

    for paper in &papers {
        let tokens: Vec<String> = paper.text.to_lowercase().split_whitespace().map(|s| s.to_string()).collect();
        for token in &tokens {
            vocab.insert(token.clone());
        }
        doc_tokens.push(tokens);
    }

    let vocab: Vec<String> = vocab.into_iter().collect();
    let mut tfidf_matrix = Vec::new();

    // Compute IDF
    let n_docs = papers.len() as f64;
    let mut idf = HashMap::new();
    for term in &vocab {
        let mut df = 0;
        for tokens in &doc_tokens {
            if tokens.contains(term) {
                df += 1;
            }
        }
        idf.insert(term.clone(), (n_docs / df as f64).ln());
    }

    // Compute TF-IDF
    for tokens in &doc_tokens {
        let mut vec = Vec::new();
        let total_terms = tokens.len();

        let mut term_counts = HashMap::new();
        for token in tokens {
            *term_counts.entry(token.clone()).or_insert(0) += 1;
        }

        for term in &vocab {
            let count = *term_counts.get(term).unwrap_or(&0);

            // INTENTIONAL BUG: integer division here causes TF to be 0 for almost everything
            let tf = (count / total_terms) as f64; 

            let idf_val = idf.get(term).unwrap();
            vec.push(tf * idf_val);
        }
        tfidf_matrix.push(vec);
    }

    // Compute Cosine Similarity and output
    let mut output = String::new();
    for i in 0..papers.len() {
        let mut scores: Vec<(usize, f64)> = Vec::new();
        for j in 0..papers.len() {
            if i == j { continue; }
            let sim = cosine_similarity(&tfidf_matrix[i], &tfidf_matrix[j]);
            scores.push((j, sim));
        }
        // Sort descending
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        output.push_str(&format!("{},{},{}\n", papers[i].id, papers[scores[0].0].id, papers[scores[1].0].id));
    }

    fs::write("/home/user/recommendations.csv", output).expect("Failed to write output");
}

fn cosine_similarity(v1: &[f64], v2: &[f64]) -> f64 {
    let mut dot = 0.0;
    let mut norm1 = 0.0;
    let mut norm2 = 0.0;

    for i in 0..v1.len() {
        dot += v1[i] * v2[i];
        norm1 += v1[i] * v1[i];
        norm2 += v2[i] * v2[i];
    }

    if norm1 == 0.0 || norm2 == 0.0 {
        return 0.0;
    }
    dot / (norm1.sqrt() * norm2.sqrt())
}
EOF

    # Fix permissions and ownership
    chown -R user:user /home/user
    chmod -R 777 /home/user
