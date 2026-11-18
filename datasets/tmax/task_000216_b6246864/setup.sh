#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /home/user/build_metrics/lib
mkdir -p /home/user/build_metrics/include

# Create stats.h
cat << 'EOF' > /home/user/build_metrics/include/stats.h
#ifndef STATS_H
#define STATS_H
void stats_init(void);
void stats_add(double value);
double stats_get_mean(void);
double stats_get_variance(void);
#endif
EOF

# Create stats.c
cat << 'EOF' > /home/user/build_metrics/stats.c
#include "include/stats.h"
static double sum = 0;
static double sq_sum = 0;
static int count = 0;

void stats_init(void) { sum = 0; sq_sum = 0; count = 0; }
void stats_add(double value) { sum += value; sq_sum += value * value; count++; }
double stats_get_mean(void) { return count == 0 ? 0 : sum / count; }
double stats_get_variance(void) { 
    if (count == 0) return 0;
    double mean = sum / count;
    return (sq_sum / count) - (mean * mean);
}
EOF

# Compile libstats.a
cd /home/user/build_metrics
gcc -c stats.c -o stats.o
ar rcs lib/libstats.a stats.o
rm stats.c stats.o

# Create slow_parser.py
cat << 'EOF' > /home/user/build_metrics/slow_parser.py
import sys
import time

def parse():
    starts = {}
    durations = []
    with open("build_trace.log", "r") as f:
        for line in f:
            time.sleep(0.00001) # artificially slow it down
            if line.startswith("START_TRACE::"):
                parts = line.strip().split("::")
                if len(parts) == 3:
                    starts[parts[1]] = int(parts[2])
            elif line.startswith("END_TRACE::"):
                parts = line.strip().split("::")
                if len(parts) == 3:
                    name = parts[1]
                    end_ts = int(parts[2])
                    if name in starts and name.startswith("mobile_module_"):
                        durations.append(end_ts - starts[name])

    if durations:
        mean = sum(durations) / len(durations)
        variance = sum((x - mean) ** 2 for x in durations) / len(durations)
        print(f"Mean: {mean:.2f}, Variance: {variance:.2f}")

if __name__ == "__main__":
    parse()
EOF
chmod +x /home/user/build_metrics/slow_parser.py

# Generate build_trace.log (Deterministic)
python3 -c '
import random
random.seed(42)
with open("/home/user/build_metrics/build_trace.log", "w") as f:
    for i in range(5000):
        target = f"mobile_module_{i}" if i % 2 == 0 else f"other_module_{i}"
        start = i * 100
        f.write(f"START_TRACE::{target}::{start}\n")
        f.write("Some random garbage log line that should be ignored\n")
        f.write("Another [INFO] garbage line\n")
        duration = random.randint(50, 500)
        f.write(f"END_TRACE::{target}::{start + duration}\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
