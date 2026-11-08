#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        openmpi-bin \
        libopenmpi-dev \
        curl

    pip3 install pytest flask redis mpi4py pandas numpy scipy matplotlib seaborn scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/simulation_app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    cat << 'EOF' > /home/user/simulation_app/start_services.sh
#!/bin/bash
# Broken startup script
redis-server &
python3 /home/user/simulation_app/api.py &
python3 /home/user/simulation_app/worker.py &
EOF
    chmod +x /home/user/simulation_app/start_services.sh

    cat << 'EOF' > /home/user/simulation_app/api.py
from flask import Flask, request
import redis
import os
import json

app = Flask(__name__)
# Broken connection string
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/submit', methods=['POST'])
def submit():
    data = request.get_json(force=True)
    r.lpush('job_queue', json.dumps(data))
    return "Job submitted\n"

if __name__ == '__main__':
    # Broken port
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/simulation_app/worker.py
import redis
import json
import time
import os
from mpi4py import MPI

comm = MPI.COMM_WORLD
rank = comm.Get_rank()

redis_url = os.environ.get('REDIS_URL', 'redis://localhost:6379')
r = redis.Redis.from_url(redis_url)

if rank == 0:
    while True:
        try:
            job = r.brpop('job_queue', timeout=1)
            if job:
                job_data = json.loads(job[1])
                with open('/home/user/simulation_app/worker.log', 'a') as f:
                    f.write(f"Processed {job_data.get('job')}\n")
        except Exception:
            pass
        time.sleep(0.1)
EOF

    cat << 'EOF' > /tmp/generate_corpus.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)

def make_clean(path):
    for i in range(10):
        step = np.arange(100)
        time = step * 0.01
        dt = np.random.normal(0.01, 0.002, 100)
        error = np.random.uniform(0, 0.1, 100)
        df = pd.DataFrame({'step': step, 'time': time, 'dt': dt, 'error': error})
        df.to_csv(f"{path}/clean_{i}.csv", index=False)

def make_evil(path):
    for i in range(10):
        step = np.arange(100)
        time = step * 0.01
        dt = np.random.normal(0.01, 0.002, 100)
        dt[80:95] = np.random.normal(1e-7, 1e-8, 15)
        error = np.random.uniform(0, 0.1, 100)
        df = pd.DataFrame({'step': step, 'time': time, 'dt': dt, 'error': error})
        df.to_csv(f"{path}/evil_{i}.csv", index=False)

make_clean('/home/user/corpus/clean')
make_evil('/home/user/corpus/evil')
EOF

    python3 /tmp/generate_corpus.py

    chmod -R 777 /home/user
