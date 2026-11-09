#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server gawk bc curl
    pip3 install pytest flask requests redis

    mkdir -p /app/perf_env
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/perf_env/config.env
REDIS_PORT=6379
FLASK_PORT=8080
API_URL=http://127.0.0.1:8080
EOF

    cat << 'EOF' > /opt/oracle/analyze_metrics_oracle
#!/usr/bin/env python3
import sys
args = [float(x) for x in sys.argv[1:]]
x = args[0::2]
y = args[1::2]
n = len(x)
sum_x = sum(x)
sum_y = sum(y)
sum_xy = sum(x[i]*y[i] for i in range(n))
sum_xx = sum(x[i]*x[i] for i in range(n))
m = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
c = (sum_y - m * sum_x) / n
residuals = [y[i] - (m * x[i] + c) for i in range(n)]
res_var = sum(r*r for r in residuals) / n
print(f"Slope: {m:.4f}, Intercept: {c:.4f}, ResidualVar: {res_var:.4f}")
EOF
    chmod +x /opt/oracle/analyze_metrics_oracle

    cat << 'EOF' > /app/perf_env/redis.conf
port 6380
daemonize no
EOF

    cat << 'EOF' > /app/perf_env/api.py
import os
from flask import Flask
import redis

app = Flask(__name__)
redis_port = int(os.environ.get('REDIS_PORT', 6379))
r = redis.Redis(host='127.0.0.1', port=redis_port, socket_timeout=1)

@app.route('/')
def index():
    r.ping()
    return "OK"

if __name__ == '__main__':
    flask_port = int(os.environ.get('FLASK_PORT', 5000))
    app.run(host='127.0.0.1', port=flask_port)
EOF

    cat << 'EOF' > /app/perf_env/load_gen.py
import os
import time
import requests

api_url = os.environ.get('API_URL', 'http://127.0.0.1:5000')

try:
    for _ in range(3):
        res = requests.get(api_url, timeout=2)
        res.raise_for_status()
        time.sleep(0.5)
    with open('/home/user/load_gen.log', 'w') as f:
        f.write("Flow Complete\n")
except Exception as e:
    with open('/home/user/load_gen.log', 'w') as f:
        f.write(f"Error: {e}\n")
EOF

    cat << 'EOF' > /app/perf_env/start_services.sh
#!/bin/bash
source /app/perf_env/config.env
export REDIS_PORT FLASK_PORT API_URL

redis-server /app/perf_env/redis.conf &
sleep 1
python3 /app/perf_env/api.py &
sleep 1
python3 /app/perf_env/load_gen.py
EOF
    chmod +x /app/perf_env/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/perf_env
