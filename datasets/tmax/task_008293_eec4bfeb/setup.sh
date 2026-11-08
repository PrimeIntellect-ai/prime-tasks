#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc patch make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/qa_env/rust_router/src
    mkdir -p /home/user/qa_env/test_env

    cat << 'EOF' > /home/user/qa_env/rust_router/Cargo.toml
[package]
name = "router_cli"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/qa_env/rust_router/src/main.rs
use std::env;
use std::collections::HashMap;

// BROKEN: Needs two lifetimes, e.g., <'a, 'b> since keys come from pattern and values from path.
struct RouteMatch<'a> {
    path: &'a str,
    params: HashMap<&'a str, &'a str>,
}

// BROKEN signature
fn extract_params(pattern: &str, path: &str) -> Option<RouteMatch> {
    let mut params = HashMap::new();
    let pat_parts: Vec<&str> = pattern.split('/').collect();
    let path_parts: Vec<&str> = path.split('/').collect();

    if pat_parts.len() != path_parts.len() { return None; }

    for (pat, p) in pat_parts.iter().zip(path_parts.iter()) {
        if pat.starts_with(':') {
            params.insert(&pat[1..], *p);
        } else if pat != p {
            return None;
        }
    }

    Some(RouteMatch { path, params })
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        return;
    }
    let pattern = &args[1];
    let path = &args[2];

    if let Some(rm) = extract_params(pattern, path) {
        let mut params_vec: Vec<_> = rm.params.iter().collect();
        params_vec.sort_by_key(|k| k.0);
        for (k, v) in params_vec {
            println!("{}:{}", k, v);
        }
    } else {
        println!("NOMATCH");
    }
}
EOF

    cat << 'EOF' > /home/user/qa_env/test_env/test_runner.py
import subprocess
import json
import os

def run_test():
    pass

if __name__ == '__main__':
    run_test()
EOF

    cat << 'EOF' > /home/user/qa_env/update.patch
--- test_env/test_runner.py
+++ test_env/test_runner.py
@@ -4,7 +4,17 @@
 import os

 def run_test():
-    pass
+    bin_path = os.path.join(os.path.dirname(__file__), '../rust_router/target/debug/router_cli')
+    routes_file = os.path.join(os.path.dirname(__file__), '../routes.json')
+    out_file = os.path.join(os.path.dirname(__file__), '../test_results.log')
+    
+    with open(routes_file, 'r') as f:
+        routes = json.load(f)
+        
+    with open(out_file, 'w') as f:
+        for r in routes:
+            res = subprocess.run([bin_path, r['pattern'], r['path']], capture_output=True, text=True)
+            f.write(f"{r['pattern']} | {r['path']} => {res.stdout.strip()}\n")

 if __name__ == '__main__':
     run_test()
EOF

    cat << 'EOF' > /home/user/qa_env/routes.json
[
  {"pattern": "/users/:id", "path": "/users/123"},
  {"pattern": "/api/v1/:resource/:action", "path": "/api/v1/posts/delete"},
  {"pattern": "/static/:file", "path": "/api/v1/posts/delete"}
]
EOF

    chmod -R 777 /home/user
