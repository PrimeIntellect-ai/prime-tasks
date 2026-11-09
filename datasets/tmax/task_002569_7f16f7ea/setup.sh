#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server cargo rustc patch curl

pip3 install pytest flask

mkdir -p /app/legacy-engine
mkdir -p /app/rust-processor/src
mkdir -p /app/rust-processor/tests
mkdir -p /app/patches

cat << 'EOF' > /app/legacy-engine/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/ast/<rule_id>', methods=['GET'])
def get_ast(rule_id):
    if request.headers.get('Authorization') != 'Bearer internal-token':
        return jsonify({"error": "Unauthorized"}), 401

    if rule_id == 'rule-prod':
        return jsonify({"type": "AND", "left": {"type": "CONSTRAINT", "value": ">=1.0.0"}, "right": {"type": "CONSTRAINT", "value": "<3.0.0"}})
    return jsonify({"type": "CONSTRAINT", "value": ">=1.0.0"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

cat << 'EOF' > /app/rust-processor/Cargo.toml
[package]
name = "rust-processor"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
reqwest = { version = "0.11", features = ["json"] }
tokio = { version = "1", features = ["full", "macros"] }
redis = { version = "0.23", features = ["tokio-comp"] }
semver = "1.0"
warp = "0.3"
EOF

cat << 'EOF' > /app/rust-processor/src/main.rs
mod evaluator;
mod cache;

use warp::Filter;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct EvalRequest {
    version: String,
    rule_id: String,
}

#[derive(Serialize)]
struct EvalResponse {
    allowed: bool,
}

#[tokio::main]
async fn main() {
    let evaluate_route = warp::post()
        .and(warp::path("evaluate"))
        .and(warp::body::json())
        .map(|_req: EvalRequest| {
            warp::reply::json(&EvalResponse { allowed: false })
        });

    warp::serve(evaluate_route).run(([127, 0, 0, 1], 8080)).await;
}
EOF

cat << 'EOF' > /app/rust-processor/src/evaluator.rs
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(tag = "type")]
pub enum AstNode {
    AND { left: Box<AstNode>, right: Box<AstNode> },
    OR { left: Box<AstNode>, right: Box<AstNode> },
    CONSTRAINT { value: String },
}

pub fn evaluate_semver_ast(_ast: &AstNode, _version: &str) -> bool {
    // TODO: implement
    false
}
EOF

cat << 'EOF' > /app/rust-processor/src/cache.rs
pub struct Cache {
    client: redis::Client,
}

impl Cache {
    pub fn new(url: &str) -> Self {
        Cache {
            client: redis::Client::open(url).unwrap(),
        }
    }
}
EOF

cat << 'EOF' > /app/patches/redis-support.patch
--- a/src/cache.rs
+++ b/src/cache.rs
@@ -1,3 +1,4 @@
+// Missing imports here
 pub struct Cache {
     client: redis::Client,
 }
@@ -8,4 +9,10 @@
             client: redis::Client::open(url).unwrap(),
         }
     }
+
+    pub async fn get(&self, key: &str) -> Option<String> {
+        let mut con = self.client.get_async_connection().await.unwrap();
+        let result: Option<String> = con.get(key).await.unwrap();
+        result
+    }
 }
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
