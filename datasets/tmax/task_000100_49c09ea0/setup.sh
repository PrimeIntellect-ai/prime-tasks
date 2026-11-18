#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3
    pip3 install pytest

    mkdir -p /home/user/pr_review
    cd /home/user/pr_review

    cat << 'EOF' > math_engine.c
#include <math.h>

double calculate_stddev(double* data, int len) {
    double sum = 0.0;
    // BUG: <= len instead of < len causes buffer over-read
    for(int i = 0; i <= len; i++) {
        sum += data[i];
    }
    double mean = sum / len;

    double variance_sum = 0.0;
    for(int i = 0; i < len; i++) {
        variance_sum += (data[i] - mean) * (data[i] - mean);
    }

    return sqrt(variance_sum / len);
}
EOF

    cat << 'EOF' > Makefile
libmath_engine.so: math_engine.c
	gcc -shared -fPIC -o libmath_engine.so math_engine.c
	# Missing math library flag here
EOF

    cat << 'EOF' > schema_v1.sql
CREATE TABLE stats (
    id INTEGER PRIMARY KEY,
    mean REAL
);
EOF

    cat << 'EOF' > schema_v2.sql
-- TODO: Add variance column of type REAL to the stats table
EOF

    cat << 'EOF' > test.py
import ctypes
import sqlite3
import sys
import os

try:
    lib = ctypes.CDLL('./libmath_engine.so')
except OSError as e:
    print(f"Failed to load libmath_engine.so: {e}")
    sys.exit(1)

lib.calculate_stddev.restype = ctypes.c_double
lib.calculate_stddev.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]

data = (ctypes.c_double * 4)(2.0, 4.0, 4.0, 4.5)
stddev = lib.calculate_stddev(data, 4)

# Basic sanity check on the bounds fix: if it read garbage memory, stddev is highly likely to be wild.
# The correct stddev for [2.0, 4.0, 4.0, 4.5] is roughly 0.98425
if not (0.9 < stddev < 1.0):
    print(f"Math output incorrect. Possible UB/memory corruption triggered. Got {stddev}")
    sys.exit(1)

conn = sqlite3.connect('test.db')
cursor = conn.cursor()
try:
    cursor.execute("INSERT INTO stats (mean, variance) VALUES (?, ?)", (3.625, stddev**2))
    conn.commit()
except sqlite3.OperationalError as e:
    print(f"DB Error: {e}")
    sys.exit(1)

print("SUCCESS")
EOF

    cat << 'EOF' > run_ci.sh
#!/bin/bash

# 1. Clean previous state
rm -f test.db libmath_engine.so /home/user/ci_success.log

# 2. Database migration
sqlite3 test.db < schema_v1.sql
sqlite3 test.db < schema_v2.sql

# 3. Build polyglot backend
make

# 4. Run tests
python3 test.py

echo "CI PASS" > /home/user/ci_success.log
EOF

    chmod +x run_ci.sh
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pr_review
    chmod -R 777 /home/user
