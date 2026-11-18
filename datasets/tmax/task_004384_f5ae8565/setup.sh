#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl gawk bc
    pip3 install pytest flask redis

    # Create directories
    mkdir -p /home/user
    mkdir -p /app/api
    mkdir -p /app/redis

    # Create sequences.fasta
    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ATGCGTA
>seq2
GCGCGC
>seq3
ATATAT
EOF

    # Create app.py
    cat << 'EOF' > /app/api/app.py
import os
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
# Agent must change 9999 to 6379
r = redis.Redis(host='127.0.0.1', port=9999, db=0, decode_responses=True)

@app.route('/api/population', methods=['GET'])
def get_pop():
    seq_id = request.args.get('seq_id')
    val = r.get(seq_id)
    if val is None:
        return jsonify({"error": "not found"}), 404
    return jsonify({"seq_id": seq_id, "population": round(float(val), 2)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    # Create start.sh
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server /app/redis/redis.conf &
python3 /app/api/app.py &
EOF
    chmod +x /app/start.sh

    # Create redis.conf
    cat << 'EOF' > /app/redis/redis.conf
port 6379
daemonize no
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chown -R user:user /app
    chmod -R 777 /home/user
    chmod -R 777 /app
