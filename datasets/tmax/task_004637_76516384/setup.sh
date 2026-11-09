#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        openmpi-bin \
        libopenmpi-dev \
        build-essential \
        curl

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/app/config
    mkdir -p /home/user/app/scripts

    # Setup virtual environment
    python3 -m venv /home/user/venv
    /home/user/venv/bin/pip install mpi4py flask requests python-dotenv

    # Create start_services.sh
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
source /home/user/venv/bin/activate
python /home/user/app/aggregator.py &
python /home/user/app/worker_daemon.py &
python /home/user/app/gateway.py &
wait
EOF
    chmod +x /home/user/app/start_services.sh

    # Create settings.env (broken ports)
    cat << 'EOF' > /home/user/app/config/settings.env
GATEWAY_PORT=8081
WORKER_PORT=5001
AGGREGATOR_PORT=9091
EOF

    # Create gateway.py
    cat << 'EOF' > /home/user/app/gateway.py
import os, requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv('/home/user/app/config/settings.env')
app = Flask(__name__)

@app.route('/simulate', methods=['POST'])
def simulate():
    data = request.json.get('data', '')
    worker_port = os.environ.get('WORKER_PORT', '5000')
    try:
        resp = requests.post(f'http://127.0.0.1:{worker_port}/process', json={'data': data})
        return jsonify(resp.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('GATEWAY_PORT', '8080'))
    app.run(host='127.0.0.1', port=port)
EOF

    # Create worker_daemon.py
    cat << 'EOF' > /home/user/app/worker_daemon.py
import os, subprocess
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv('/home/user/app/config/settings.env')
app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    data = request.json.get('data', '')
    with open('/tmp/raw_data.csv', 'w') as f:
        f.write(data)

    subprocess.run(['/home/user/app/scripts/reshape_data.sh', '/tmp/raw_data.csv', '/tmp/reshaped.dat'])
    subprocess.run(['/home/user/app/scripts/run_mpi_sim.sh', '/tmp/reshaped.dat'])

    return jsonify({"status": "processing"})

if __name__ == '__main__':
    port = int(os.environ.get('WORKER_PORT', '5000'))
    app.run(host='127.0.0.1', port=port)
EOF

    # Create aggregator.py
    cat << 'EOF' > /home/user/app/aggregator.py
import os, socket, threading
from dotenv import load_dotenv

load_dotenv('/home/user/app/config/settings.env')
result_val = 0.0

def handle_client(conn):
    global result_val
    try:
        data = conn.recv(1024).decode().strip()
        if data.startswith('RESULT '):
            result_val = float(data.split()[1])
        elif data == 'GET_RESULTS':
            conn.sendall(str(result_val).encode() + b'\n')
    except:
        pass
    finally:
        conn.close()

def main():
    port = int(os.environ.get('AGGREGATOR_PORT', '9090'))
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', port))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle_client, args=(conn,)).start()

if __name__ == '__main__':
    main()
EOF

    # Create reshape_data.sh (broken)
    cat << 'EOF' > /home/user/app/scripts/reshape_data.sh
#!/bin/bash
# Broken: does not filter error > 0.5, does not convert to space-separated
cat $1 > $2
EOF
    chmod +x /home/user/app/scripts/reshape_data.sh

    # Create run_mpi_sim.sh (broken)
    cat << 'EOF' > /home/user/app/scripts/run_mpi_sim.sh
#!/bin/bash
# Broken: does not load venv, runs with -n 2 instead of 4
mpirun --allow-run-as-root -n 2 python /home/user/app/simulator.py $1
EOF
    chmod +x /home/user/app/scripts/run_mpi_sim.sh

    # Create simulator.py (broken dt)
    cat << 'EOF' > /home/user/app/simulator.py
import sys, socket, os
from mpi4py import MPI
from dotenv import load_dotenv

load_dotenv('/home/user/app/config/settings.env')

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

# Broken: step size too large, causes divergence
dt = 1.0

if rank == 0:
    val = 10.0
    for _ in range(int(1.0/dt)):
        val -= val * dt

    port = int(os.environ.get('AGGREGATOR_PORT', '9090'))
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(('127.0.0.1', port))
        s.sendall(f"RESULT {val}\n".encode())
        s.close()
    except:
        pass
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
