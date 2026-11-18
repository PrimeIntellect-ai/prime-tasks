#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /home/user/app
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/app/config.ini
[DEFAULT]
REDIS_HOST = localhost
REDIS_PORT = 6379
PRE_FILTER_CMD = /bin/true
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/app/api.py &
python3 /home/user/app/worker.py &
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask, request
import subprocess
import configparser
import redis
import os

app = Flask(__name__)
config = configparser.ConfigParser()
config.read('/home/user/app/config.ini')
r = redis.Redis(host=config['DEFAULT']['REDIS_HOST'], port=int(config['DEFAULT']['REDIS_PORT']))

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files['file']
    filepath = '/tmp/temp.csv'
    file.save(filepath)
    cmd = config['DEFAULT']['PRE_FILTER_CMD']
    if cmd == '/bin/true':
        ret = 0
    else:
        ret = subprocess.call([cmd, filepath])
    if ret == 0:
        with open(filepath, 'r') as f:
            r.rpush('data_queue', f.read())
        return "Accepted", 200
    else:
        return "Rejected", 400

if __name__ == '__main__':
    app.run(port=8080)
EOF

    cat << 'EOF' > /home/user/app/worker.py
import redis
import configparser
import time

config = configparser.ConfigParser()
config.read('/home/user/app/config.ini')
r = redis.Redis(host=config['DEFAULT']['REDIS_HOST'], port=int(config['DEFAULT']['REDIS_PORT']))

while True:
    item = r.blpop('data_queue', timeout=1)
    if item:
        pass
    time.sleep(0.1)
EOF

    python3 -c "
import random
import os

clean_dir = '/home/user/corpora/clean'
evil_dir = '/home/user/corpora/evil'

def write_csv(path, header, rows):
    with open(path, 'w') as f:
        f.write(header + '\n')
        for r in rows:
            f.write(','.join(map(str, r)) + '\n')

# Generate 50 clean
for i in range(50):
    rows = []
    for j in range(10):
        rows.append([j, random.uniform(-1000, 1000), random.uniform(-1000, 1000), random.choice([0, 1])])
    write_csv(f'{clean_dir}/clean_{i}.csv', 'id,feature_A,feature_B,target', rows)

# Generate 50 evil
for i in range(10):
    # Missing feature_A
    rows = [[j, '', random.uniform(-1000, 1000), random.choice([0, 1])] for j in range(5)]
    write_csv(f'{evil_dir}/evil_missing_A_{i}.csv', 'id,feature_A,feature_B,target', rows)

    # feature_A > 1000
    rows = [[j, random.uniform(1000.1, 2000), random.uniform(-1000, 1000), random.choice([0, 1])] for j in range(5)]
    write_csv(f'{evil_dir}/evil_high_A_{i}.csv', 'id,feature_A,feature_B,target', rows)

    # feature_A < -1000
    rows = [[j, random.uniform(-2000, -1000.1), random.uniform(-1000, 1000), random.choice([0, 1])] for j in range(5)]
    write_csv(f'{evil_dir}/evil_low_A_{i}.csv', 'id,feature_A,feature_B,target', rows)

    # target missing or = 2
    t = random.choice(['', 2])
    rows = [[j, random.uniform(-1000, 1000), random.uniform(-1000, 1000), t] for j in range(5)]
    write_csv(f'{evil_dir}/evil_target_{i}.csv', 'id,feature_A,feature_B,target', rows)

    # malformed header
    rows = [[j, random.uniform(-1000, 1000), random.uniform(-1000, 1000), random.choice([0, 1])] for j in range(5)]
    write_csv(f'{evil_dir}/evil_header_{i}.csv', 'id,feature_A,feature_B,wrong_target', rows)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
