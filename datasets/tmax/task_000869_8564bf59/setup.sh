#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server g++ libomp-dev libeigen3-dev curl
    pip3 install pytest flask redis

    mkdir -p /app/spatial_pipeline/api
    mkdir -p /app/spatial_pipeline/worker

    cat << 'EOF' > /app/spatial_pipeline/api/app.py
import os
import json
import subprocess
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
REDIS_HOST = os.environ.get('REDIS_HOST', 'db_host_placeholder')
redis_client = redis.Redis(host=REDIS_HOST, port=6379, db=0)

@app.route('/analyze', methods=['POST'])
def analyze():
    data = request.json
    seq_id = data.get('sequence_id')
    time_end = data.get('time_end', 10.0)

    D = redis_client.get(seq_id)
    if not D:
        return jsonify({"error": "Sequence not found"}), 404

    D = float(D)

    cmd = ["/app/spatial_pipeline/worker/pde_worker", str(D), str(time_end), f"/home/user/output_mode_{seq_id}.txt"]
    subprocess.run(cmd, check=True)

    return jsonify({"status": "success", "message": "Analysis complete"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/spatial_pipeline/worker/pde_worker.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <Eigen/Dense>
#include <omp.h>

using namespace std;
using namespace Eigen;

int main(int argc, char** argv) {
    if (argc < 4) return 1;
    double D = stod(argv[1]);
    double time_end = stod(argv[2]);
    string out_file = argv[3];

    int nx = 100;
    double dx = 1.0 / (nx - 1);

    double dt = 0.1; 

    int nt = time_end / dt;
    if (nt <= 0) nt = 1;

    MatrixXd history(nx, nt);
    vector<double> u(nx, 0.0);
    u[nx/2] = 1.0; 

    for (int t = 0; t < nt; ++t) {
        for (int i = 0; i < nx; ++i) {
            history(i, t) = u[i];
        }

        vector<double> unew = u;
        for (int i = 1; i < nx - 1; ++i) {
            unew[i] = u[i] + D * dt / (dx * dx) * (u[i+1] - 2*u[i] + u[i-1]);
        }
        u = unew;
    }

    JacobiSVD<MatrixXd> svd(history, ComputeThinU | ComputeThinV);
    VectorXd mode = svd.matrixV().col(0); 

    ofstream out(out_file);
    for (int i = 0; i < nx; ++i) {
        out << mode(i);
        if (i < nx - 1) out << ",";
    }
    out << endl;
    return 0;
}
EOF

    cat << 'EOF' > /app/spatial_pipeline/setup_redis.sh
#!/bin/bash
redis-server --daemonize yes
sleep 1
redis-cli set SEQ_99 2.5
EOF
    chmod +x /app/spatial_pipeline/setup_redis.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
