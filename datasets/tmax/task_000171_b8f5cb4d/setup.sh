#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        imagemagick \
        fonts-dejavu-core \
        gcc \
        make \
        libc6-dev

    pip3 install pytest

    mkdir -p /app

    # Generate the image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -annotate +20+50 "RATE LIMIT SPECIFICATIONS\n\nMax Capacity: 500 tokens\nRefill Rate: 10 tokens per millisecond" /app/rate_limit_specs.png

    # Create ratelimit.c
    cat << 'EOF' > /app/ratelimit.c
#include <stdbool.h>
#include <time.h>
#include <stdint.h>

// TODO: Read specs from rate_limit_specs.png and implement token bucket
// state variables here.

#ifndef OPTIMIZED_BUILD
#error "OPTIMIZED_BUILD macro must be defined"
#endif

// TODO: Implement allow_request() and ensure it can be called from Python ctypes
EOF

    # Create Makefile
    cat << 'EOF' > /app/Makefile
# Broken Makefile
all:
	gcc ratelimit.c -o libratelimit.so
EOF

    # Create validator.py
    cat << 'EOF' > /app/validator.py
import time
import ctypes

class PurePythonRateLimiter:
    def __init__(self):
        self.capacity = 500
        self.tokens = 500
        self.refill_rate = 10 # per ms
        self.last_time = time.time() * 1000

    def allow_request(self):
        now = time.time() * 1000
        elapsed = now - self.last_time
        self.tokens += elapsed * self.refill_rate
        if self.tokens > self.capacity:
            self.tokens = self.capacity
        self.last_time = now

        if self.tokens >= 1:
            self.tokens -= 1
            return True
        return False

class CRateLimiter:
    def __init__(self):
        pass # TODO: Load libratelimit.so via ctypes

    def allow_request(self):
        return False # TODO: Call the C function
EOF

    # Create benchmark.py
    cat << 'EOF' > /app/benchmark.py
import time
from validator import PurePythonRateLimiter, CRateLimiter

def run_bench(limiter, iterations=500000):
    start = time.time()
    allowed = 0
    for _ in range(iterations):
        if limiter.allow_request():
            allowed += 1
    end = time.time()
    return end - start, allowed

py_limiter = PurePythonRateLimiter()
c_limiter = CRateLimiter()

print("Warming up...")
run_bench(py_limiter, 10000)
run_bench(c_limiter, 10000)

print("Benchmarking Python...")
py_time, py_allowed = run_bench(py_limiter)

print("Benchmarking C...")
c_time, c_allowed = run_bench(c_limiter)

speedup = py_time / c_time if c_time > 0 else 0
print(f"Python time: {py_time:.4f}s")
print(f"C time: {c_time:.4f}s")
print(f"Speedup: {speedup:.2f}x")

if speedup >= 5.0:
    print("Threshold met!")

with open('/app/speedup.txt', 'w') as f:
    f.write(str(speedup))
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
