#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline_proj
    cd /home/user/pipeline_proj
    cargo init --name pipeline_proj
    cargo add serde_json

    cat << 'EOF' > /home/user/pipeline_proj/reference.py
import json

def transform(data):
    parsed = json.loads(data)
    return [item['name'].upper() for item in parsed if item.get('active', False)]
EOF

    cat << 'EOF' > /home/user/pipeline_proj/generate_data.py
import json
data = [
    {"name": "alice", "active": True},
    {"name": "bob", "active": False},
    {"name": "charlie", "active": True}
]
print(json.dumps(data))
EOF

    cat << 'EOF' > /home/user/pipeline_proj/src/transformer.rs
use serde_json::Value;

pub fn transform(data: &str) -> Vec<&str> {
    let parsed: Value = serde_json::from_str(data).unwrap();
    let mut result = Vec::new();
    if let Some(arr) = parsed.as_array() {
        for item in arr {
            if item["active"].as_bool().unwrap_or(false) {
                let upper = item["name"].as_str().unwrap().to_uppercase();
                result.push(upper.as_str()); // BUG: returning reference to local String
            }
        }
    }
    result
}
EOF

    cat << 'EOF' > /home/user/pipeline_proj/src/main.rs
mod transformer;
use std::io::{self, Read};

fn main() {
    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer).unwrap();
    let results = transformer::transform(&buffer);
    for r in results {
        println!("{}", r);
    }
}
EOF

    cat << 'EOF' > /home/user/pipeline_proj/e2e_test.sh
#!/bin/bash
# TODO: compile project
# TODO: pipe python output to rust binary
# Write SUCCESS or FAILURE to /home/user/test_results.log
EOF

    chmod +x /home/user/pipeline_proj/generate_data.py
    chmod +x /home/user/pipeline_proj/e2e_test.sh

    chmod -R 777 /home/user
