#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest h5py biopython redis flask

    mkdir -p /app/data/samples
    mkdir -p /app/test_data/clean
    mkdir -p /app/test_data/evil

    cat << 'EOF' > /tmp/gen_data.py
import os
import random

def create_fasta(path, num_seqs, contamination_rate, primer):
    with open(path, 'w') as f:
        for i in range(num_seqs):
            is_contaminated = random.random() < contamination_rate
            seq = "A" * 50
            if is_contaminated:
                seq = seq[:10] + primer + seq[10+len(primer):]
            f.write(f">seq{i}\n{seq}\n")

primer = "GATCGGAAGAGCACACGTCTG"
os.makedirs("/app/test_data/clean", exist_ok=True)
os.makedirs("/app/test_data/evil", exist_ok=True)
os.makedirs("/app/data/samples", exist_ok=True)

for i in range(50):
    create_fasta(f"/app/test_data/clean/clean_{i}.fasta", 100, 0.01, primer)
    create_fasta(f"/app/test_data/evil/evil_{i}.fasta", 100, 0.10, primer)
    create_fasta(f"/app/data/samples/sample_{i}.fasta", 100, random.choice([0.01, 0.10]), primer)
EOF
    python3 /tmp/gen_data.py

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
if [ -f /home/user/services.env ]; then
    source /home/user/services.env
fi

redis-server --port ${REDIS_PORT:-6379} --daemonize yes

cat << 'PYEOF' > /tmp/api.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def hello():
    return "OK"
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
PYEOF
python3 /tmp/api.py &

cat << 'PYEOF' > /tmp/worker.py
import os
import redis
import time

try:
    r = redis.Redis(host=os.environ.get('REDIS_HOST', '127.0.0.1'), port=int(os.environ.get('REDIS_PORT', 6379)))
    time.sleep(2)
    r.set('pipeline_status', 'COMPLETED')
    with open('/home/user/worker.log', 'w') as f:
        f.write('PIPELINE_SUCCESS\n')
except Exception as e:
    pass
PYEOF
python3 /tmp/worker.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
