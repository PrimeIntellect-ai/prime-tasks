#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make redis-server wget curl
    pip3 install pytest flask numpy

    mkdir -p /app

    cat << 'EOF' > /app/data_api.py
from flask import Flask, jsonify
import numpy as np

app = Flask(__name__)

mean = np.array([5.0, -3.0])
cov = np.array([[1.0, 0.999], [0.999, 1.0]])

@app.route('/data')
def get_data():
    samples = np.random.multivariate_normal(mean, cov, 100)
    return jsonify(samples.tolist())

@app.route('/truth')
def get_truth():
    return jsonify({"mean": mean.tolist(), "cov": cov.tolist()})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /app/data_api.py > /app/api.log 2>&1 &
EOF
    chmod +x /app/start_services.sh

    mkdir -p /home/user/worker

    cat << 'EOF' > /home/user/worker/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -O2

all: estimator

estimator: estimator.cpp
	$(CXX) $(CXXFLAGS) -o estimator estimator.cpp -lpthread

clean:
	rm -f estimator
EOF

    cat << 'EOF' > /home/user/worker/estimator.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include "httplib.h"
#include "json.hpp"

using json = nlohmann::json;
using namespace std;

// TODO: Implement KL divergence, Tikhonov regularization, and convergence test.

int main() {
    cout << "Starting estimator..." << endl;
    // Fetch data, estimate parameters, check convergence

    return 0;
}
EOF

    cd /home/user/worker
    wget -q https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h
    wget -q https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
