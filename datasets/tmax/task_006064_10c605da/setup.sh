#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output
    mkdir -p /home/user/nlp_tools/src

    cat << 'EOF' > /home/user/data/corpus.txt
The quick brown fox jumps over the lazy dog.
The dog barks at the fox, but the fox is quick.
A quick brown dog is a happy dog.
Foxes are quick, but dogs are lazy.
The quick brown fox is quick and the lazy dog is lazy.
EOF

    cd /home/user/nlp_tools
    cargo init --bin

    cat << 'EOF' > /home/user/nlp_tools/src/main.rs
use std::fs;
use std::collections::HashMap;

fn main() {
    let content = fs::read_to_string("/home/user/data/corpus.txt").expect("Failed to read file");
    let docs: Vec<&str> = content.lines().collect();

    let mut doc_tokens: Vec<Vec<String>> = Vec::new();
    let mut global_counts: HashMap<String, usize> = HashMap::new();

    for doc in &docs {
        // BUG: This keeps ONLY whitespace and punctuation, discarding letters.
        let cleaned: String = doc.to_lowercase()
            .chars()
            .filter(|c| !c.is_alphabetic()) 
            .collect();

        let tokens: Vec<String> = cleaned.split_whitespace().map(|s| s.to_string()).collect();
        doc_tokens.push(tokens.clone());

        for token in tokens {
            if !token.is_empty() {
                *global_counts.entry(token).or_insert(0) += 1;
            }
        }
    }

    let mut count_vec: Vec<(&String, &usize)> = global_counts.iter().collect();
    count_vec.sort_by(|a, b| b.1.cmp(a.1).then(a.0.cmp(b.0)));

    let top_3: Vec<String> = count_vec.into_iter().take(3).map(|(k, _)| k.clone()).collect();

    fs::write("/home/user/output/top_tokens.txt", top_3.join("\n")).expect("Write failed");

    let n = docs.len() as f64;
    if n <= 1.0 || top_3.is_empty() {
        fs::write("/home/user/output/covariance.csv", "0.0000,0.0000,0.0000\n0.0000,0.0000,0.0000\n0.0000,0.0000,0.0000\n").unwrap();
        return;
    }

    let mut freqs: Vec<Vec<f64>> = vec![vec![0.0; 3]; docs.len()];
    for (i, tokens) in doc_tokens.iter().enumerate() {
        for (j, top_word) in top_3.iter().enumerate() {
            freqs[i][j] = tokens.iter().filter(|&t| t == top_word).count() as f64;
        }
    }

    let mut means = vec![0.0; 3];
    for i in 0..3 {
        let sum: f64 = freqs.iter().map(|f| f[i]).sum();
        means[i] = sum / n;
    }

    let mut cov_matrix = vec![vec![0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            let mut cov_sum = 0.0;
            for k in 0..docs.len() {
                cov_sum += (freqs[k][i] - means[i]) * (freqs[k][j] - means[j]);
            }
            cov_matrix[i][j] = cov_sum / (n - 1.0);
        }
    }

    let mut csv_out = String::new();
    for i in 0..3 {
        csv_out.push_str(&format!("{:.4},{:.4},{:.4}\n", cov_matrix[i][0], cov_matrix[i][1], cov_matrix[i][2]));
    }

    fs::write("/home/user/output/covariance.csv", csv_out).expect("Write failed");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
