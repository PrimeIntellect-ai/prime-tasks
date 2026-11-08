#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl gcc libc6-dev
    pip3 install pytest flask redis

    mkdir -p /app/services/api
    cat << 'EOF' > /app/services/api/app.py
import os
import redis
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/tune', methods=['POST'])
def tune():
    host = os.environ.get('REDIS_HOST')
    port = os.environ.get('REDIS_PORT')
    if not host or not port:
        return jsonify({"error": "Redis configuration missing"}), 500

    try:
        r = redis.Redis(host=host, port=int(port))
        r.set('cv_alpha', '4.2500')
        r.set('cv_beta', '1.8000')
        return jsonify({"status": "success", "cv_alpha": 4.2500, "cv_beta": 1.8000})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/bayes_filter.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    double x;
    double alpha = 4.2500;
    double beta = 1.8000;
    while (scanf("%lf", &x) == 1) {
        double y = (x + alpha) / (beta + 1.0);
        printf("%.4f\n", y);
    }
    return 0;
}
EOF
    gcc -O3 /opt/oracle/bayes_filter.c -o /opt/oracle/bayes_filter

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
