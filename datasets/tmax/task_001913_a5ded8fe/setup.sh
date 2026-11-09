#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server g++ make libhiredis-dev
pip3 install pytest fastapi uvicorn redis numpy pandas scipy requests python-dotenv

mkdir -p /app/api /app/worker /app/data

# Create /app/start_services.sh
cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/api && uvicorn server:app --host 0.0.0.0 --port 8000 &
cd /app/worker && ./worker &
wait
EOF
chmod +x /app/start_services.sh

# Create /app/api/.env (buggy)
cat << 'EOF' > /app/api/.env
REDIS_HOST=127.0.0.1
REDIS_PORT=6380
EOF

# Create /app/api/server.py
cat << 'EOF' > /app/api/server.py
from fastapi import FastAPI
from pydantic import BaseModel
import redis
import json
import uuid
import time
import os
from dotenv import load_dotenv

load_dotenv()
app = FastAPI()

r = redis.Redis(host=os.getenv("REDIS_HOST", "127.0.0.1"), port=int(os.getenv("REDIS_PORT", 6379)), decode_responses=True)

class Params(BaseModel):
    k1: float
    k2: float
    k3: float

@app.post("/simulate")
def simulate(params: Params):
    job_id = str(uuid.uuid4())
    payload = f"{job_id} {params.k1} {params.k2} {params.k3}"
    r.lpush("job_queue", payload)

    # Wait for result
    for _ in range(50):
        res = r.get(f"result_{job_id}")
        if res:
            return json.loads(res)
        time.sleep(0.1)
    return {"error": "timeout"}
EOF

# Create /app/worker/config.ini (buggy)
cat << 'EOF' > /app/worker/config.ini
redis_host=127.0.0.1
redis_port=6380
EOF

# Create /app/worker/integrator.cpp (buggy)
cat << 'EOF' > /app/worker/integrator.cpp
#include <iostream>
#include <vector>
#include <cmath>

using namespace std;

// Simulate A -> B -> P
// dA/dt = -k1 * A
// dB/dt = k1 * A - k2 * B
// dP/dt = k3 * B
// k3 is a simplified catalytic rate.

void derivs(double t, const vector<double>& y, vector<double>& dydt, double k1, double k2, double k3) {
    dydt[0] = -k1 * y[0];
    dydt[1] = k1 * y[0] - k2 * y[1];
    dydt[2] = k3 * y[1];
}

string integrate(double k1, double k2, double k3) {
    vector<double> y = {10.0, 0.0, 0.0}; // A, B, P
    double t = 0.0;
    double t_end = 10.0;
    double dt = 0.1;
    double tolerance = 1e-4;

    string res = "{\"t\": [";
    string res_P = "], \"P\": [";

    while (t < t_end) {
        res += to_string(t) + ",";
        res_P += to_string(y[2]) + ",";

        vector<double> dydt(3);
        derivs(t, y, dydt, k1, k2, k3);

        // Simplified RK1 for demonstration, with fake adaptive step
        double error = 1e-2; // Fake error
        // BUG: inverted step size logic
        double dt_new = dt * pow(error / tolerance, 0.25);

        // Prevent infinite loop in buggy state by capping dt
        if (dt_new < 1e-5) dt_new = 1e-5;
        if (dt_new > 1.0) dt_new = 1.0;

        for (int i=0; i<3; ++i) y[i] += dydt[i] * dt;
        t += dt;
        dt = dt_new;
    }

    res.pop_back();
    res_P.pop_back();
    return res + res_P + "]}";
}
EOF

# Create /app/worker/worker.cpp
cat << 'EOF' > /app/worker/worker.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <hiredis/hiredis.h>

using namespace std;

string integrate(double k1, double k2, double k3);

int main() {
    ifstream config("config.ini");
    string host = "127.0.0.1";
    int port = 6379;
    string line;
    while (getline(config, line)) {
        if (line.find("redis_port=") != string::npos) {
            port = stoi(line.substr(11));
        }
    }

    redisContext *c = redisConnect(host.c_str(), port);
    if (c == NULL || c->err) {
        cout << "Connection error" << endl;
        return 1;
    }

    while (true) {
        redisReply *reply = (redisReply*)redisCommand(c, "BRPOP job_queue 1");
        if (reply && reply->type == REDIS_REPLY_ARRAY && reply->elements == 2) {
            string payload = reply->element[1]->str;
            stringstream ss(payload);
            string job_id;
            double k1, k2, k3;
            ss >> job_id >> k1 >> k2 >> k3;

            string result = integrate(k1, k2, k3);

            string cmd = "SET result_" + job_id + " '" + result + "'";
            redisReply *set_reply = (redisReply*)redisCommand(c, cmd.c_str());
            freeReplyObject(set_reply);
        }
        if (reply) freeReplyObject(reply);
    }
    return 0;
}
EOF

# Create /app/worker/Makefile
cat << 'EOF' > /app/worker/Makefile
all: worker

worker: worker.cpp integrator.cpp
	g++ -O3 worker.cpp integrator.cpp -o worker -lhiredis

clean:
	rm -f worker
EOF

# Compile worker initially
cd /app/worker && make

# Create observed data
cat << 'EOF' > /app/data/observed.csv
t,P
0.0,0.0
1.0,0.5
2.0,1.8
3.0,3.2
4.0,4.5
5.0,5.6
6.0,6.5
7.0,7.2
8.0,7.8
9.0,8.2
10.0,8.5
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
