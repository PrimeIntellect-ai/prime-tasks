#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-pip wget g++ make libeigen3-dev redis-server curl

pip3 install pytest flask requests matplotlib redis gunicorn numpy

mkdir -p /app/engine
mkdir -p /app/frontend

wget https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -O /usr/local/include/httplib.h
wget https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp -O /usr/local/include/json.hpp

cat << 'EOF' > /app/engine/compute.cpp
#include <iostream>
#include "httplib.h"
#include "json.hpp"
#include <Eigen/Dense>

using json = nlohmann::json;

int main() {
    httplib::Server svr;

    svr.Post("/solve", [](const httplib::Request& req, httplib::Response& res) {
        auto j = json::parse(req.body);
        std::vector<std::vector<double>> A_vec = j["A"];
        std::vector<double> b_vec = j["b"];

        int n = A_vec.size();
        Eigen::MatrixXd A(n, n);
        Eigen::VectorXd b(n);

        for (int i = 0; i < n; ++i) {
            b(i) = b_vec[i];
            for (int k = 0; k < n; ++k) {
                A(i, k) = A_vec[i][k];
            }
        }

        // Flawed direct inverse
        Eigen::VectorXd x = A.inverse() * b;

        std::vector<double> x_vec(x.data(), x.data() + x.size());
        json res_j;
        res_j["x"] = x_vec;
        res.set_content(res_j.dump(), "application/json");
    });

    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

cat << 'EOF' > /app/engine/Makefile
all:
	g++ -O3 -std=c++11 compute.cpp -o compute -I/usr/include/eigen3 -lpthread
EOF

cat << 'EOF' > /app/frontend/app.py
import os
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

COMPUTE_URL = os.environ.get("COMPUTE_URL", "http://127.0.0.1:8080")

@app.route('/health', methods=['GET'])
def health():
    return "OK", 200

@app.route('/simulate', methods=['POST'])
def simulate():
    data = request.json
    size = data.get("size", 10)
    anisotropy = data.get("anisotropy", 0.9)

    n = size * size
    A = [[0.0]*n for _ in range(n)]
    b = [1.0]*n

    for i in range(n):
        A[i][i] = 4.0
        if i % size != 0: A[i][i-1] = -1.0
        if (i+1) % size != 0: A[i][i+1] = -1.0
        if i >= size: A[i][i-size] = -anisotropy
        if i < n - size: A[i][i+size] = -anisotropy

    if anisotropy > 0.99:
        for i in range(n):
            A[i][i] = 2.0 * anisotropy
            if i % size != 0: A[i][i-1] = -anisotropy
            if (i+1) % size != 0: A[i][i+1] = -anisotropy

    resp = requests.post(f"{COMPUTE_URL}/solve", json={"A": A, "b": b})
    res_data = resp.json()
    return jsonify({"state": res_data["x"]})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
# TODO: Fix and complete this startup script
EOF
chmod +x /app/start_services.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
