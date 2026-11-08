#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest fastapi uvicorn redis scipy numpy matplotlib requests

    mkdir -p /home/user/app/data/clean
    mkdir -p /home/user/app/data/evil

    # Create dummy data
    cat << 'EOF' > /home/user/app/data/clean/clean1.csv
id,amount,location_frequency
1,10.5,5
2,15.0,4
EOF

    cat << 'EOF' > /home/user/app/data/evil/evil1.csv
id,amount,location_frequency
3,10000.0,1
4,5000.0,0
EOF

    # Create .env with wrong config
    cat << 'EOF' > /home/user/app/.env
REDIS_URL=redis://wronghost:6379/0
API_PORT=9999
EOF

    # Create start_services.sh
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
uvicorn api:app --host 0.0.0.0 --port 8000 &
python3 worker.py &
EOF
    chmod +x /home/user/app/start_services.sh

    # Create detector.py
    cat << 'EOF' > /home/user/app/detector.py
def classify(csv_row_dict):
    return True
EOF

    # Create plot_results.py
    cat << 'EOF' > /home/user/app/plot_results.py
import matplotlib.pyplot as plt

def plot():
    plt.figure()
    plt.plot([1, 2, 3], [1, 4, 9])
    plt.savefig('/home/user/app/summary.png')

if __name__ == '__main__':
    plot()
EOF

    # Create verify.py
    cat << 'EOF' > /home/user/app/verify.py
import os
import requests
import time

def verify():
    print("Verifying...")

if __name__ == '__main__':
    verify()
EOF

    # Create api.py
    cat << 'EOF' > /home/user/app/api.py
from fastapi import FastAPI
import os
import redis

app = FastAPI()

@app.post("/ingest")
def ingest(data: dict):
    return {"status": "ok"}
EOF

    # Create worker.py
    cat << 'EOF' > /home/user/app/worker.py
import time
import os
from detector import classify

def work():
    while True:
        time.sleep(1)

if __name__ == '__main__':
    work()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
