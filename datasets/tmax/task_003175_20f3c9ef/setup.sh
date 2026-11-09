#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest flask

    mkdir -p /app

    # Create log_generator.py
    cat << 'EOF' > /app/log_generator.py
import os
import time
import random

log_path = os.environ.get("LOG_PATH", "/var/log/telemetry/usage.log")
os.makedirs(os.path.dirname(log_path), exist_ok=True)

while True:
    cpu = random.randint(0, 100)
    mem = random.randint(0, 8192)
    io = random.randint(0, 500)
    line = f"CPU:{cpu} MEM:{mem} IO:{io}\n"
    try:
        with open(log_path, "a") as f:
            f.write(line)
    except:
        pass
    time.sleep(1)
EOF
    chmod +x /app/log_generator.py

    # Create telemetry_api.py
    cat << 'EOF' > /app/telemetry_api.py
import os
from flask import Flask, jsonify

app = Flask(__name__)
data_source = os.environ.get("DATA_SOURCE", "/var/log/telemetry/usage.log")

@app.route('/metrics')
def metrics():
    try:
        with open(data_source, "r") as f:
            lines = f.readlines()
            if lines:
                last_line = lines[-1].strip()
                parts = dict(p.split(":") for p in last_line.split())
                return jsonify({"status": "ok", "latest_cpu": int(parts.get("CPU", 0))})
            else:
                return jsonify({"status": "empty"}), 404
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    chmod +x /app/telemetry_api.py

    # Create prom_scraper.sh
    cat << 'EOF' > /app/prom_scraper.sh
#!/bin/bash
while true; do
    curl -s http://localhost:5000/metrics >> /home/user/scraper_output.log
    echo "" >> /home/user/scraper_output.log
    sleep 1
done
EOF
    chmod +x /app/prom_scraper.sh

    # Create oracle_forecaster source and compile it
    cat << 'EOF' > /app/oracle_forecaster.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    int cpu = 0, mem = 0, io = 0;
    sscanf(input, "CPU:%d MEM:%d IO:%d", &cpu, &mem, &io);
    int score = (cpu * 2) + (mem / 4) + (int)(io * 1.5);
    printf("%d\n", score);
    return 0;
}
EOF
    gcc /app/oracle_forecaster.c -o /app/oracle_forecaster
    rm /app/oracle_forecaster.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
