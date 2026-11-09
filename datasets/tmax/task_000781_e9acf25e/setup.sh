#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make
    pip3 install pytest

    mkdir -p /app
    git clone https://github.com/codeplea/tinyexpr /app/tinyexpr

    cat << 'EOF' > /app/tinyexpr/Makefile
CC = gcc
CFLAGS = -Wall -Werror -fPIC -O0

libtinyexpr.so: tinyexpr.c
	$(CC) $(CFLAGS) -shared -o libtinyexpr.so tinyexpr.c

clean:
	rm -f libtinyexpr.so
EOF

    mkdir -p /app/tinyexpr-py

    cat << 'EOF' > /app/tinyexpr-py/te_wrapper.py
import ctypes
import os

lib = ctypes.CDLL(os.path.abspath('/app/tinyexpr/libtinyexpr.so'))

# PERTURBATION: Incorrect ABI types
# Should be:
# lib.te_interp.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
# lib.te_interp.restype = ctypes.c_double
lib.te_interp.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
lib.te_interp.restype = ctypes.c_int # This truncates doubles to ints

def evaluate(expression: str) -> float:
    expr_bytes = expression.encode('utf-8')
    err = ctypes.c_int(0)
    # Should be ctypes.byref(err)
    result = lib.te_interp(expr_bytes, ctypes.byref(err))
    if err.value != 0:
        raise ValueError(f"Parse error at position {err.value}")
    return float(result)
EOF

    cat << 'EOF' > /app/tinyexpr-py/test_te.py
import pytest
import math
from te_wrapper import evaluate

def test_basic_math():
    assert math.isclose(evaluate("2+2"), 4.0)
    assert math.isclose(evaluate("3.5*2.0"), 7.0)

def test_trig():
    assert math.isclose(evaluate("sin(pi/2)"), 1.0, abs_tol=1e-5)

@pytest.fixture
def mock_env():
    # The contributor forgot to yield the actual setup
    # Should be: yield {"var": 42.0}
    pass

def test_emulator(mock_env):
    # We are supposed to inject variables, but the basic wrapper doesn't support it yet.
    # The test just ensures basic evaluation doesn't crash on standard math.
    assert evaluate("sqrt(16)") == 4.0
EOF

    cat << 'EOF' > /app/tinyexpr-py/benchmark.py
import time
import json
from te_wrapper import evaluate

expressions = [f"sin({i} * 3.14159 / 180) + cos({i} * 3.14159 / 180)**2" for i in range(10000)]

# Benchmark Pure Python
start = time.time()
py_results = []
for expr in expressions:
    import math
    # Hack to make eval work with sin/cos
    py_results.append(eval(expr, {"sin": math.sin, "cos": math.cos}))
py_time = time.time() - start

# Benchmark TinyExpr
start = time.time()
te_results = []
for expr in expressions:
    te_results.append(evaluate(expr))
te_time = time.time() - start

# Compute MSE
mse = sum((p - t)**2 for p, t in zip(py_results, te_results)) / len(expressions)
speedup = py_time / te_time

results = {
    "mse": mse,
    "speedup": speedup,
    "py_time": py_time,
    "te_time": te_time
}

with open("results.json", "w") as f:
    json.dump(results, f, indent=2)

print(f"MSE: {mse}")
print(f"Speedup: {speedup:.2f}x")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
