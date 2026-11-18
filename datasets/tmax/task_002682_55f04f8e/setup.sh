#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc redis-server curl
pip3 install pytest flask redis gunicorn python-dotenv

mkdir -p /app/libthermal /app/services/api /app/bin

cat << 'EOF' > /app/libthermal/thermal.c
int get_diffusion_rate(void) {
    return 4;
}
EOF

cat << 'EOF' > /app/services/api/app.py
import os
from flask import Flask, request
import redis
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
redis_host = os.environ.get("REDIS_HOST", "invalid_host")
r = redis.Redis(host=redis_host, port=6379, db=0)

@app.route("/init", methods=["GET"])
def init():
    return "10 100 0 0 0 0 0 0 0 0 100"

@app.route("/submit", methods=["POST"])
def submit():
    data = request.get_data(as_text=True)
    r.set("final_mesh", data)
    return "OK"

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080)
EOF

cat << 'EOF' > /app/services/api/.env
REDIS_HOST=invalid_host
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/services/api
gunicorn -w 1 -b 127.0.0.1:8080 app:app --daemon
EOF
chmod +x /app/start_services.sh

cat << 'EOF' > /app/bin/mesh_step_oracle.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int N;
    if (scanf("%d", &N) != 1) return 1;
    int *V = malloc(N * sizeof(int));
    for (int i = 0; i < N; i++) {
        if (scanf("%d", &V[i]) != 1) return 1;
    }
    int *V_new = malloc(N * sizeof(int));
    V_new[0] = V[0];
    V_new[N-1] = V[N-1];
    int K = 4;
    for (int i = 1; i < N - 1; i++) {
        V_new[i] = V[i] + (V[i-1] - 2*V[i] + V[i+1]) / K;
    }
    for (int i = 0; i < N; i++) {
        printf("%d%c", V_new[i], i == N-1 ? '\n' : ' ');
    }
    free(V);
    free(V_new);
    return 0;
}
EOF

gcc -O3 /app/bin/mesh_step_oracle.c -o /app/bin/mesh_step_oracle
chmod +x /app/bin/mesh_step_oracle

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
