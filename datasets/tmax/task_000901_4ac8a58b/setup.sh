#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install --no-cache-dir pytest fastapi uvicorn numpy pydantic

    # Create vendored package
    mkdir -p /app/vendored/fast-variance/fast_variance
    cat << 'EOF' > /app/vendored/fast-variance/setup.py
from setuptools import setup, find_packages
setup(name="fast-variance", version="1.0.0", packages=find_packages())
EOF

    cat << 'EOF' > /app/vendored/fast-variance/fast_variance/__init__.py
from .core import VarianceCalculator
EOF

    cat << 'EOF' > /app/vendored/fast-variance/fast_variance/core.py
class VarianceCalculator:
    _scratch_pad = []

    def calculate(self, data):
        self._scratch_pad.clear()
        if not data: return 0.0
        mean = sum(data) / len(data)
        for x in data:
            self._scratch_pad.append((x - mean) ** 2)
        return sum(self._scratch_pad) / len(data)
EOF

    pip3 install -e /app/vendored/fast-variance

    # Create math-service repo
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/math-service
    cd /home/user/math-service
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > app.py
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
import math
from fast_variance import VarianceCalculator

app = FastAPI()
security = HTTPBearer()

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if credentials.credentials != "calc-token-998":
        raise HTTPException(status_code=401, detail="Unauthorized")
    return credentials.credentials

class DataInput(BaseModel):
    data: list[float]

@app.post("/sum")
def sum_data(input: DataInput, token: str = Depends(verify_token)):
    return {"result": math.fsum(input.data)}

@app.post("/variance")
def variance_data(input: DataInput, token: str = Depends(verify_token)):
    calc = VarianceCalculator()
    return {"result": calc.calculate(input.data)}
EOF

    git add app.py
    git commit -m "Initial commit"

    for i in {1..4}; do
        echo "# dummy $i" >> app.py
        git commit -am "Dummy commit $i"
    done

    cat << 'EOF' > app.py
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
import math
from fast_variance import VarianceCalculator

app = FastAPI()
security = HTTPBearer()

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if credentials.credentials != "calc-token-998":
        raise HTTPException(status_code=401, detail="Unauthorized")
    return credentials.credentials

class DataInput(BaseModel):
    data: list[float]

@app.post("/sum")
def sum_data(input: DataInput, token: str = Depends(verify_token)):
    import numpy as np
    total = np.float32(0.0)
    for x in input.data:
        total += np.float32(x)
    return {"result": float(total)}

@app.post("/variance")
def variance_data(input: DataInput, token: str = Depends(verify_token)):
    calc = VarianceCalculator()
    return {"result": calc.calculate(input.data)}
EOF

    git commit -am "Optimize sum"

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
