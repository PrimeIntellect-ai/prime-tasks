#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv curl
    pip3 install pytest numpy h5py flask requests scipy

    mkdir -p /app

    cat << 'EOF' > /app/data_server.py
from flask import Flask, send_file
import os

app = Flask(__name__)

@app.route('/data')
def get_data():
    return send_file('/app/spectro_data.h5', as_attachment=True)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

    cat << 'EOF' > /app/processor_api.py
from flask import Flask, jsonify
import requests
import h5py
import numpy as np
import os

app = Flask(__name__)

@app.route('/solve', methods=['GET'])
def solve():
    # TODO: Implement the solution
    pass

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8082)
EOF

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
# TODO: Activate virtual environment

# TODO: Start services in the background
EOF
    chmod +x /app/startup.sh

    cat << 'EOF' > /tmp/gen_data.py
import h5py
import numpy as np

np.random.seed(42)
M = np.random.rand(50, 20)
b = np.random.rand(50)

with h5py.File('/app/spectro_data.h5', 'w') as f:
    f.create_dataset('spectroscopy/raw', data=M)
    f.create_dataset('spectroscopy/vector', data=b)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
