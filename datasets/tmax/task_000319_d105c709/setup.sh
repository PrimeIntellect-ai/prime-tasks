#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest fastapi uvicorn hypothesis httpx requests

    mkdir -p /home/user/api
    cd /home/user/api

    cat << 'EOF' > math_eval.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

double evaluate_hex_expr(const char* hex_str) {
    if (!hex_str) return 0.0;
    int len = strlen(hex_str);
    if (len % 2 != 0) return -1.0;

    char* expr = malloc(len / 2 + 1);
    for(int i = 0; i < len / 2; i++) {
        sscanf(hex_str + 2*i, "%2hhx", &expr[i]);
    }
    expr[len/2] = '\0';

    double result = 0.0;
    char* token = strtok(expr, "+");
    while(token) {
        result += atof(token);
        token = strtok(NULL, "+");
    }

    free(expr);
    return result;
}
EOF

    cat << 'EOF' > Makefile
all:
	gcc -shared -o libmatheval.so -fPIC math_eval.c
EOF

    cat << 'EOF' > main.py
from fastapi import FastAPI
from pydantic import BaseModel
import ctypes

app = FastAPI()

# BUG: ctypes.CDLL("libmatheval.so") will fail unless LD_LIBRARY_PATH is set or an absolute path is used.
# The agent must fix this line (e.g. to ctypes.CDLL("./libmatheval.so") or os.path.abspath)
lib = ctypes.CDLL("libmatheval.so")

lib.evaluate_hex_expr.restype = ctypes.c_double
lib.evaluate_hex_expr.argtypes = [ctypes.c_char_p]

class ExprRequest(BaseModel):
    expression: str

@app.post("/evaluate")
def evaluate(req: ExprRequest):
    # BUG: Fails to convert to hex string
    raw_bytes = req.expression.encode('utf-8')
    result = lib.evaluate_hex_expr(raw_bytes)
    return {"result": result}
EOF

    cat << 'EOF' > requirements.txt
fastapi
uvicorn
pytest
hypothesis
httpx
EOF

    make

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
