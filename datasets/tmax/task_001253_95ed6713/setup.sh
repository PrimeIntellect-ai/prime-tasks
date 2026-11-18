#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nodejs npm
pip3 install pytest requests setuptools

mkdir -p /home/user/polymath/node_api
mkdir -p /home/user/polymath/python_client/poly_calc

# Node.js Setup
cat << 'EOF' > /home/user/polymath/node_api/package.json
{
  "name": "math-api",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat << 'EOF' > /home/user/polymath/node_api/server.js
const express = require('express');
const app = express();
app.use(express.json());

// TODO: Implement POST /calc endpoint here

const port = process.env.PORT || 8080;
const server = app.listen(port, () => {
    console.log(`Server listening on port ${port}`);
});

process.on('SIGTERM', () => {
    server.close();
});
EOF

# Python Setup
cat << 'EOF' > /home/user/polymath/python_client/setup.py
from setuptools import setup, find_packages
# TODO: Implement custom build command to run npm install and bundle node_api

setup(
    name="poly_calc",
    version="0.1.0",
    packages=find_packages(),
    # Missing cmdclass and package_data setup
)
EOF

cat << 'EOF' > /home/user/polymath/python_client/poly_calc/__init__.py
import subprocess
import requests
import time
import os
import signal

class PolyCalcClient:
    def __init__(self, port=8080):
        self.port = port
        self.process = None
        self.base_url = f"http://127.0.0.1:{self.port}"

    def start_server(self):
        current_dir = os.path.dirname(os.path.abspath(__file__))
        server_path = os.path.join(current_dir, "node_api", "server.js")
        self.process = subprocess.Popen(
            ["node", server_path],
            env=dict(os.environ, PORT=str(self.port)),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        time.sleep(2) # wait for server to start

    def stop_server(self):
        if self.process:
            self.process.terminate()
            self.process.wait()

    def evaluate(self, expr):
        response = requests.post(f"{self.base_url}/calc", json={"expression": expr})
        return response.json()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
