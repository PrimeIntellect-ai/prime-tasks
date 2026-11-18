#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/profiling_sim

    cat << 'EOF' > /home/user/profiling_sim/matrix_ops.c
#include <math.h>
double compute_norm(double x, double y) {
    return pow(x, 2) + pow(y, 2);
}
EOF

    cat << 'EOF' > /home/user/profiling_sim/build.sh
#!/bin/bash
gcc -shared -o libmatrix.so -fPIC matrix_ops.c
EOF
    chmod +x /home/user/profiling_sim/build.sh

    cat << 'EOF' > /home/user/profiling_sim/simulate.py
import ctypes
import sqlite3
import time

# Load the C library
try:
    lib = ctypes.CDLL('./libmatrix.so')
    lib.compute_norm.argtypes = [ctypes.c_double, ctypes.c_double]
    lib.compute_norm.restype = ctypes.c_double
except OSError:
    print("Error loading libmatrix.so. Did it compile successfully?")
    exit(1)

# Recursive square root calculation using Newton's method
def calculate_sqrt(n, guess=1.0):
    next_guess = 0.5 * (guess + n / guess)
    # BUG: Precision loss causes infinite recursion for some numbers
    if guess == next_guess:
        return guess
    return calculate_sqrt(n, next_guess)

def run_simulation():
    conn = sqlite3.connect('metrics.db')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS runs (id INTEGER PRIMARY KEY, duration REAL)')
    c.execute('DELETE FROM runs')

    # Run 5 iterations
    for i in range(5):
        start = time.time()

        # Call C library
        lib.compute_norm(3.0, 4.0)

        # Calculate sqrt of a number known to cause float oscillation in Newton's method
        res = calculate_sqrt(2.0)

        duration = (time.time() - start) * 1000 # ms
        # Mocking fixed duration for predictable testing result
        duration = 15.5 + i 

        c.execute('INSERT INTO runs (duration) VALUES (?)', (duration,))

    conn.commit()

    # BUG: Retrieves SUM instead of AVG
    c.execute('SELECT SUM(duration) FROM runs')
    avg_time = c.fetchone()[0]

    print(f"Average execution time: {avg_time} ms")

if __name__ == "__main__":
    run_simulation()
EOF

    chmod -R 777 /home/user
