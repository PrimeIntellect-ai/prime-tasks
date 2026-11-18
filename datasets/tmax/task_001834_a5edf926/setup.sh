#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ redis-server curl
    pip3 install pytest flask redis pyyaml

    # Create app directory and services script
    mkdir -p /app
    cat << 'EOF' > /app/app.py
from flask import Flask, request
app = Flask(__name__)

@app.route('/process_batch', methods=['POST'])
def process_batch():
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --port 8001 &
python3 /app/app.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    # Create user home and config
    mkdir -p /home/user
    touch /home/user/app_config.yaml

    # Create corpus directories and files
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    cat << 'EOF' > /home/user/corpus/clean/safe1.csv
tx_id,resource_id,action
T1,R1,ACQUIRE
T1,R2,ACQUIRE
T1,R2,RELEASE
T1,R1,RELEASE
T2,R1,ACQUIRE
EOF

    cat << 'EOF' > /home/user/corpus/evil/cycle1.csv
tx_id,resource_id,action
T1,R1,ACQUIRE
T2,R2,ACQUIRE
T1,R2,ACQUIRE
T2,R1,ACQUIRE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
