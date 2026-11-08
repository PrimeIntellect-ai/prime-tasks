#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nodejs npm curl
    pip3 install pytest redis

    mkdir -p /app
    cd /app
    npm init -y
    npm install redis

    cat << 'EOF' > /app/emitter.py
import time
import json
import random
import redis

r = redis.Redis(host='localhost', port=6379, db=0)
langs = ["fr", "de", "es", "ja"]
t = 10.0
while True:
    time.sleep(0.5)
    t += random.uniform(0.1, 5.0)
    event = {
        "timestamp": round(t, 1),
        "source_len": random.randint(1, 50),
        "target_len": random.randint(1, 150),
        "lang": random.choice(langs)
    }
    r.rpush("loc_raw_stream", json.dumps(event))
EOF

    cat << 'EOF' > /app/dashboard.js
const http = require('http');
const redis = require('redis');

const client = redis.createClient({ url: 'redis://localhost:6379' });
client.connect();

let events = [];

async function poll() {
    while (true) {
        try {
            const res = await client.blPop('loc_processed_stream', 1);
            if (res) {
                events.push(JSON.parse(res.element));
                if (events.length > 100) events.shift();
            }
        } catch (e) {
            // ignore timeout
        }
    }
}
poll();

http.createServer((req, res) => {
    if (req.url === '/metrics') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(events));
    } else {
        res.writeHead(404);
        res.end();
    }
}).listen(8080);
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/loc_filter_oracle
#!/usr/bin/env python3
import sys
import json

def main():
    prev_time = None
    prev_lang = None
    window = []

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except Exception:
            continue

        curr_time = event["timestamp"]

        if prev_time is not None:
            diff = curr_time - prev_time
            if diff > 2.0:
                syn_time = prev_time + 1.0
                while round(syn_time, 1) < curr_time:
                    gap = {
                        "timestamp": round(syn_time, 1),
                        "source_len": 0,
                        "target_len": 0,
                        "lang": prev_lang,
                        "anomaly": False,
                        "is_gap": True
                    }
                    print(json.dumps(gap))
                    syn_time += 1.0

        anomaly = False
        if len(window) == 5 and event["source_len"] > 0:
            avg_ratio = sum(window) / 5.0
            curr_ratio = event["target_len"] / event["source_len"]
            if curr_ratio > 2.0 * avg_ratio:
                anomaly = True

        event["anomaly"] = anomaly
        event["is_gap"] = False
        print(json.dumps(event))

        if event["source_len"] > 0:
            window.append(event["target_len"] / event["source_len"])
            if len(window) > 5:
                window.pop(0)

        prev_time = curr_time
        prev_lang = event["lang"]

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/loc_filter_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
