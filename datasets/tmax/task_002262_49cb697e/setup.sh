#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server g++ curl
    pip3 install pytest redis flask

    mkdir -p /home/user/logs/raw \
             /home/user/logs/archive \
             /home/user/corpus/clean \
             /home/user/corpus/evil \
             /app

    cat << 'EOF' > /app/frontend.py
import redis
from flask import Flask, request

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/', methods=['POST'])
def receive():
    data = request.get_data()
    r.rpush('log_queue', data)
    return "OK\n"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /app/archiver.sh
#!/bin/bash
while true; do
    item=$(redis-cli --raw BLPOP log_queue 0 | tail -n 1)
    if [ ! -z "$item" ]; then
        timestamp=$(date +%s%N)
        echo -n "$item" > "/home/user/logs/raw/$timestamp.bin"
    fi
done
EOF
    chmod +x /app/archiver.sh

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/frontend.py &
/app/archiver.sh &
EOF
    chmod +x /app/startup.sh

    # Generate corpus files
    python3 -c '
import struct
import os

def write_record(f, payload):
    f.write(struct.pack("<I", 0xDEADBEEF))
    f.write(struct.pack("<I", len(payload)))
    f.write(payload)

clean_dir = "/home/user/corpus/clean"
evil_dir = "/home/user/corpus/evil"

for i in range(50):
    with open(os.path.join(clean_dir, f"clean_{i}.bin"), "wb") as f:
        write_record(f, b"INFO: All good\nLine 2\nLine 3 AAAA")

    with open(os.path.join(evil_dir, f"evil_{i}.bin"), "wb") as f:
        if i % 2 == 0:
            write_record(f, b"INFO: Bad log\nSTATUS: FATAL_BLOAT\nLine 3")
        else:
            write_record(f, b"INFO: Something [CORRUPT] here\nLine 2")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
