#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip patch
pip3 install pytest

mkdir -p /home/user/project

cat << 'EOF' > /home/user/project/api.py
from math_ops import matrix_multiply

def logger(msg):
    print("LOG:", msg)

def run_api():
    return matrix_multiply([[1, 2], [3, 4]], [[5, 6], [7, 8]])
EOF

cat << 'EOF' > /home/user/project/math_ops.py
def matrix_multiply(a, b):
    return [[sum(x * y for x, y in zip(row, col)) for col in zip(*b)] for row in a]
EOF

cat << 'EOF' > /home/user/project/test_api.py
from api import run_api, fast_exp_api

def test_run():
    assert run_api() == [[19, 22], [43, 50]]

def test_exp():
    assert fast_exp_api() == 1024
EOF

cat << 'EOF' > /home/user/pr.patch
--- project/api.py
+++ project/api.py
@@ -5,3 +5,6 @@

 def run_api():
     return matrix_multiply([[1, 2], [3, 4]], [[5, 6], [7, 8]])
+
+def fast_exp_api():
+    from math_ops import fast_exp
+    return fast_exp(2, 10)
--- project/math_ops.py
+++ project/math_ops.py
@@ -1,2 +1,7 @@
+from api import logger
+
 def matrix_multiply(a, b):
     return [[sum(x * y for x, y in zip(row, col)) for col in zip(*b)] for row in a]
+
+def fast_exp(base, exp):
+    logger(f"Calculating {base}^{exp}")
+    return base ** exp
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
