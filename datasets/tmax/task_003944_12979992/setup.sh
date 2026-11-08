#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget curl
    pip3 install pytest pandas

    mkdir -p /app/simdjson/singleheader
    mkdir -p /home/user

    # Download simdjson 3.6.0 singleheader files
    wget -qO /app/simdjson/singleheader/simdjson.h https://raw.githubusercontent.com/simdjson/simdjson/v3.6.0/singleheader/simdjson.h
    wget -qO /app/simdjson/singleheader/simdjson.cpp https://raw.githubusercontent.com/simdjson/simdjson/v3.6.0/singleheader/simdjson.cpp

    # Create baseline.py
    cat << 'EOF' > /app/baseline.py
import sys
import json
import pandas as pd

def main():
    input_file = sys.argv[1] if len(sys.argv) > 1 else "/home/user/server_logs.jsonl"
    output_file = sys.argv[2] if len(sys.argv) > 2 else "/tmp/ref.csv"

    data = []
    with open(input_file, 'r') as f:
        for line in f:
            try:
                record = json.loads(line)
                if record.get("status") == 200 and "endpoint" in record and "latency_ms" in record:
                    data.append({
                        "endpoint": record["endpoint"],
                        "latency_ms": float(record["latency_ms"])
                    })
            except:
                pass

    df = pd.DataFrame(data)
    if df.empty:
        pd.DataFrame(columns=["endpoint","count","avg_latency","max_latency"]).to_csv(output_file, index=False)
        return

    summary = df.groupby("endpoint").agg(
        count=("latency_ms", "count"),
        avg_latency=("latency_ms", "mean"),
        max_latency=("latency_ms", "max")
    ).reset_index()

    summary = summary.sort_values("endpoint")
    summary["avg_latency"] = summary["avg_latency"].round(4)
    summary["max_latency"] = summary["max_latency"].round(4)

    summary.to_csv(output_file, index=False, float_format='%.4f')

if __name__ == "__main__":
    main()
EOF

    # Create build.sh with the incorrect -std=c++11 flag
    cat << 'EOF' > /app/build.sh
#!/bin/bash
g++ -O3 -std=c++11 /home/user/analyzer.cpp /app/simdjson/singleheader/simdjson.cpp -o /home/user/log_analyzer
EOF
    chmod +x /app/build.sh

    # Generate mock log data
    cat << 'EOF' > /tmp/generate_logs.py
import json
import random

endpoints = ["/api/login", "/api/data", "/api/users", "/api/settings", "/api/checkout"]
statuses = [200, 200, 200, 404, 500, 403]

with open("/home/user/server_logs.jsonl", "w") as f:
    for _ in range(500000):
        log = {
            "endpoint": random.choice(endpoints),
            "status": random.choice(statuses),
            "latency_ms": round(random.uniform(10.0, 500.0), 4)
        }
        # Occasionally drop fields to test validation
        if random.random() < 0.01:
            log.pop("status")
        elif random.random() < 0.01:
            log.pop("latency_ms")
        f.write(json.dumps(log) + "\n")
EOF
    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
