#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask celery redis scipy numpy jupyter papermill biopython

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app /home/user/data

    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
daemon off;
error_log /dev/stderr info;
events {
    worker_connections 1024;
}
http {
    access_log /dev/stdout;
    server {
        listen 8080;
        location /simulate {
            # TODO: Add proxy_pass directive here
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask, request, jsonify
from worker import simulate_pcr

app = Flask(__name__)

@app.route('/simulate', methods=['POST'])
def simulate():
    data = request.json
    if not data or 'sequence' not in data:
        return jsonify({"error": "Missing sequence"}), 400
    seq = data['sequence']
    task = simulate_pcr.delay(seq)
    return jsonify({"task_id": task.id}), 202

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/app/worker.py
from celery import Celery
import numpy as np
from scipy.integrate import solve_ivp

app = Celery('worker', broker='redis://localhost:6379/0', backend='redis://localhost:6379/0')

def pcr_kinetics(t, y, seq):
    # Dummy ODE that gets stiff if GC > 80% or long AT repeats
    gc_content = (seq.count('G') + seq.count('C')) / len(seq) if len(seq) > 0 else 0
    stiff = gc_content > 0.8 or 'ATATATATAT' in seq
    k = 1000 if stiff else 1
    return [-k * y[0], k * y[0]]

@app.task
def simulate_pcr(seq):
    # RK45 will fail on stiff problems (mimicking the step-size adaptation failure)
    sol = solve_ivp(pcr_kinetics, [0, 10], [1.0, 0.0], args=(seq,), method='RK45')
    if not sol.success:
        raise RuntimeError("Integration failed due to stiffness")
    return sol.y.tolist()
EOF

    cat << 'EOF' > /home/user/data/clean_sequences.fasta
>clean1
ATGCGTACGTAGCTAGCTAG
>clean2
CGTAGCTAGCTAGCTAGCTA
>clean3
ATCGATCGATCGATCGATCG
EOF

    cat << 'EOF' > /home/user/data/evil_sequences.fasta
>evil1_high_gc
GCGCGCGCGCGCGCGCGCGC
>evil2_high_gc
CCGGCCGGCCGGCCGGCCGG
>evil3_tandem_at
ATATATATATATATATATAT
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
