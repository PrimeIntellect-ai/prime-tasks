#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/text_analyzer/src

    cat << 'EOF' > /home/user/dataset.csv
id,text,label
1,apple is a fruit,A
2,banana is yellow,A
bad,invalid id,B
3,,A
4,carrot is a vegetable,B
5,dog barks,C
6,cat meows loudly,C
7,elephant is big,C
8,frog jumps high,C
9,grape is purple,A
10,horse runs fast,C
11,iguana is a lizard,C
12,juice is sweet,A
13,kite flies in the sky,B
14,lemon is sour,A
15,monkey climbs trees,C
16,nut is hard,A
17,owl hoots at night,C
18,penguin swims well,C
19,quail is a bird,C
20,rabbit hops around,C
21,snake slithers slowly,C
22,tiger roars fiercely,C
EOF

    cat << 'EOF' > /home/user/text_analyzer/Cargo.toml
[package]
name = "text_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/text_analyzer/src/embedding.rs
pub fn embed(text: &str) -> Vec<f32> {
    // BUG: Always returns 0s
    vec![0.0, 0.0, 0.0, 0.0, 0.0]
}
EOF

    cat << 'EOF' > /home/user/text_analyzer/src/main.rs
mod embedding;

fn main() {
    println!("Please implement the text analyzer here.");
}
EOF

    chmod -R 777 /home/user
