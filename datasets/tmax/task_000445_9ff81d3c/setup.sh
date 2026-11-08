#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo redis-server
    pip3 install pytest flask redis python-dotenv

    mkdir -p /app/redis
    mkdir -p /app/api

    cat << 'EOF' > /app/redis/redis.conf
port 6385
daemonize yes
EOF

    cat << 'EOF' > /app/api/.env
REDIS_PORT=6379
EOF

    cat << 'EOF' > /app/api/server.py
import os
import random
from flask import Flask, Response
import redis
from dotenv import load_dotenv

load_dotenv(dotenv_path="/app/api/.env")

app = Flask(__name__)
redis_port = int(os.environ.get("REDIS_PORT", 6379))
r = redis.Redis(host='127.0.0.1', port=redis_port, db=0)

@app.route('/dataset')
def dataset():
    # Check redis connection
    try:
        r.ping()
    except redis.exceptions.ConnectionError:
        return "Redis connection failed", 500

    def generate_fasta():
        for i in range(5000):
            L = random.randint(18, 30)
            GC = random.randint(5, L)
            true_tm = 22.0 + 0.3 * L + 1.2 * GC + random.gauss(0, 0.1)

            # Generate sequence
            seq = []
            for _ in range(GC):
                seq.append(random.choice(['G', 'C']))
            for _ in range(L - GC):
                seq.append(random.choice(['A', 'T']))
            random.shuffle(seq)
            seq_str = "".join(seq)

            yield f">seq{i} tm={true_tm:.4f}\n{seq_str}\n"

    return Response(generate_fasta(), mimetype='text/plain')

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server /app/redis/redis.conf
python3 /app/api/server.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
