#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest fastapi uvicorn redis scipy numpy requests pydantic

    mkdir -p /app

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
uvicorn lab_api:app --host 0.0.0.0 --port 8000 &
uvicorn evaluator_api:app --host 0.0.0.0 --port 8001 &
wait
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/lab_api.py
import os
import redis
import numpy as np
from fastapi import FastAPI
from scipy.integrate import solve_ivp

redis_host = os.environ.get("REDIS_HOST")
if not redis_host:
    raise ValueError("REDIS_HOST environment variable is not set")

r = redis.Redis(host=redis_host, port=6379, db=0)
r.ping()

app = FastAPI()

@app.get("/sequences")
def get_sequences():
    return [
        "ATGCGTACGTAGCTAGCTAGCGTACG",
        "ATGCGTACGTAGCTAGCTAGCGTACG",
        "ATGCGTACGTAGCTAGCTAGCGTACG",
        "ATGCGTACGTACCTAGCTAGCGTACG",
        "ATGCGTACGTAGCTAGCTAGCGTACG"
    ]

@app.get("/kinetics")
def get_kinetics():
    def ode_system(t, y, k1, k2):
        P, A = y
        dP_dt = -k1 * P * A
        dA_dt = k1 * P * A - k2 * A
        return [dP_dt, dA_dt]

    t_eval = np.linspace(0, 100, 50)
    sol = solve_ivp(ode_system, [0, 100], [55.0, 0.01], args=(0.08, 0.02), t_eval=t_eval)

    np.random.seed(42)
    fluorescence = sol.y[1] + np.random.normal(0, 0.05, len(t_eval))
    fluorescence = np.maximum(fluorescence, 0)

    return {
        "time": t_eval.tolist(),
        "fluorescence": fluorescence.tolist()
    }
EOF

    cat << 'EOF' > /app/evaluator_api.py
import os
import redis
import numpy as np
from fastapi import FastAPI
from pydantic import BaseModel
from scipy.integrate import solve_ivp

redis_host = os.environ.get("REDIS_HOST")
if not redis_host:
    raise ValueError("REDIS_HOST environment variable is not set")

r = redis.Redis(host=redis_host, port=6379, db=0)
r.ping()

app = FastAPI()

class Submission(BaseModel):
    k1: float
    k2: float
    gc_content: float

@app.post("/submit")
def submit(sub: Submission):
    def ode_system(t, y, k1, k2):
        P, A = y
        dP_dt = -k1 * P * A
        dA_dt = k1 * P * A - k2 * A
        return [dP_dt, dA_dt]

    t_eval = np.linspace(0, 100, 50)
    sol_true = solve_ivp(ode_system, [0, 100], [55.0, 0.01], args=(0.08, 0.02), t_eval=t_eval)
    sol_pred = solve_ivp(ode_system, [0, 100], [sub.gc_content, 0.01], args=(sub.k1, sub.k2), t_eval=t_eval)

    mse = np.mean((sol_true.y[1] - sol_pred.y[1])**2)
    return {"status": "success", "mse": float(mse)}
EOF

    cat << 'EOF' > /app/requirements.txt
fastapi
uvicorn
redis
scipy
numpy
requests
pydantic
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
