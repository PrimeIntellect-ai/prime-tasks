#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/legacy_pipeline
    mkdir -p /home/user/migrator/build

    cat << 'EOF' > /home/user/legacy_pipeline/math_core.py
# SCHEMA_VERSION: v1.1
# WEIGHT_FACTOR: 10
def add(a, b):
    return a + b
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/calc_utils.py
# DEPENDS_ON: math_core.py
# SCHEMA_VERSION: v1.4
# WEIGHT_FACTOR: 5
import math_core
def double_add(a, b):
    return math_core.add(a, b) * 2
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/matrix_ops.py
# DEPENDS_ON: math_core.py
# SCHEMA_VERSION: v2.1
# WEIGHT_FACTOR: 8
import math_core
def matrix_add(m1, m2):
    pass
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/data_transform.py
# DEPENDS_ON: calc_utils.py, matrix_ops.py
# SCHEMA_VERSION: v1.2
# WEIGHT_FACTOR: 15
import calc_utils
import matrix_ops
def transform(data):
    pass
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/report_gen.py
# DEPENDS_ON: data_transform.py
# SCHEMA_VERSION: v3.0
# WEIGHT_FACTOR: 2
import data_transform
def generate_report():
    print "Done"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
