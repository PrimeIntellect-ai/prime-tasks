#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis rq python-dotenv

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /submit {
            # proxy_pass directive missing
        }
    }
}
EOF

    cat << 'EOF' > /app/worker.env
REDIS_URL=redis://127.0.0.1:9999/0
EOF

    cat << 'EOF' > /app/api_server.py
from flask import Flask, request
from redis import Redis
from rq import Queue
import os

app = Flask(__name__)
redis_conn = Redis.from_url(os.getenv('REDIS_URL', 'redis://127.0.0.1:6379/0'))
q = Queue(connection=redis_conn)

def process_job(fasta_content):
    pass # worker will execute this

@app.route('/submit', methods=['POST'])
def submit():
    fasta = request.data.decode('utf-8')
    q.enqueue('worker.process_job', fasta)
    return "Job submitted", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/worker.py
import os
import subprocess
from redis import Redis
from rq import Worker, Queue, Connection
from dotenv import load_dotenv

load_dotenv('/app/worker.env')

def process_job(fasta_content):
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.fasta') as f:
        f.write(fasta_content)
        tmp_name = f.name

    result = subprocess.run(['/home/user/filter.sh', tmp_name], capture_output=True)

    with open('/app/results.log', 'a') as log:
        if result.returncode == 0:
            log.write("ACCEPTED\n")
        else:
            log.write("REJECTED\n")

    os.remove(tmp_name)

if __name__ == '__main__':
    redis_url = os.getenv('REDIS_URL')
    redis_conn = Redis.from_url(redis_url)
    with Connection(redis_conn):
        worker = Worker(['default'])
        worker.work()
EOF

    cat << 'EOF' > /app/corpus/clean/clean1.fasta
>clean1
ATGCATGCATGC
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.fasta
>clean2
ATCGATCGATCG
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.fasta
>evil1
ATGCGCGCGCGCAT
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.fasta
>evil2
ATGGGGGGGGAT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
