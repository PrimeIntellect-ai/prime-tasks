#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx cargo gunicorn
    pip3 install pytest flask redis

    mkdir -p /home/user
    useradd -m -s /bin/bash user || true

    # Create raw telemetry file
    python3 -c "import random, string; f=open('/home/user/raw_telemetry.txt', 'w'); f.write('\n'.join([''.join(random.choices(string.ascii_letters, k=20)) for _ in range(50000)]) + '\n'); f.close()"

    # Create Rust project
    mkdir -p /home/user/telemetry_fmt/src
    cat << 'EOF' > /home/user/telemetry_fmt/Cargo.toml
[package]
name = "telemetry_fmt"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/telemetry_fmt/src/main.rs
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    let prefix = String::from("MOBILE_V1:");
    for line in stdin.lock().lines() {
        let l = line.unwrap();
        // Intentional borrow checker error: moving prefix inside the loop
        let out = prefix + &l;
        println!("{}", out);
    }
}
EOF

    # Create services
    mkdir -p /app/services
    cat << 'EOF' > /app/services/api.py
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/api/batch', methods=['POST'])
def batch():
    data = request.json
    if not data or 'telemetry' not in data:
        return jsonify({"error": "Invalid payload"}), 400
    pipe = r.pipeline()
    for item in data['telemetry']:
        pipe.lpush('telemetry_data', item)
    pipe.execute()
    return jsonify({"status": "ok", "inserted": len(data['telemetry'])}), 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/services/start_services.sh
#!/bin/bash
service redis-server start
gunicorn -w 4 -b 127.0.0.1:5000 api:app --chdir /app/services --daemon
service nginx start
EOF
    chmod +x /app/services/start_services.sh

    chmod -R 777 /home/user
    chmod -R 777 /app
