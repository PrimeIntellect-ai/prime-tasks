#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas

    mkdir -p /app

    cat << 'EOF' > /app/.hidden_agg.py
import sys
import pandas as pd
import re

def process(log_path):
    data = []
    pattern = re.compile(r'\[(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] Sensor:(?P<sensor_id>S\d{2}) Val:(?P<reading>-?\d+\.\d+) Diag:(?P<diag>[A-Z0-9]+)')
    with open(log_path, 'r') as f:
        for line in f:
            m = pattern.search(line)
            if m:
                ts = m.group('timestamp')
                sensor = m.group('sensor_id')
                val = float(m.group('reading'))
                diag = m.group('diag')
                if -100.0 <= val <= 1000.0 and (diag.startswith('OK') or diag.startswith('WARN')):
                    data.append({'timestamp': ts, 'sensor': sensor, 'val': val})
    if not data:
        print("timestamp_hour")
        return
    df = pd.DataFrame(data)
    df['timestamp'] = pd.to_datetime(df['timestamp'])
    df['timestamp_hour'] = df['timestamp'].dt.floor('h')
    df = df.groupby(['timestamp_hour', 'sensor'])['val'].mean().reset_index()
    df = df.pivot(index='timestamp_hour', columns='sensor', values='val')
    df.index = df.index.strftime('%Y-%m-%dT%H:00:00')
    df.to_csv(sys.stdout, na_rep='')

if __name__ == '__main__':
    process(sys.argv[1])
EOF

    cat << 'EOF' > /app/legacy_aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        usleep(5000);
    }
    fclose(f);
    char cmd[512];
    sprintf(cmd, "python3 /app/.hidden_agg.py %s", argv[1]);
    system(cmd);
    return 0;
}
EOF

    gcc -O2 /app/legacy_aggregator.c -o /app/legacy_aggregator
    strip -s /app/legacy_aggregator
    rm /app/legacy_aggregator.c

    cat << 'EOF' > /tmp/generate_logs.py
import random
from datetime import datetime, timedelta

def generate_log(path, num_lines):
    start_time = datetime(2023, 1, 1, 0, 0, 0)
    with open(path, 'w') as f:
        for i in range(num_lines):
            ts = (start_time + timedelta(minutes=i*5)).strftime('%Y-%m-%dT%H:%M:%S')
            sensor = f"S{random.randint(1, 5):02d}"
            val = round(random.uniform(-150.0, 1100.0), 2)
            diag = random.choice(['OK', 'WARN', 'ERR', 'FAIL']) + str(random.randint(10, 99))
            f.write(f"[{ts}] Sensor:{sensor} Val:{val} Diag:{diag}\n")

generate_log('/home/user/sample.log', 500)
generate_log('/tmp/eval_telemetry.log', 50000)
EOF

    useradd -m -s /bin/bash user || true
    python3 /tmp/generate_logs.py

    cat << 'EOF' > /verify_metric.py
import sys
import time
import subprocess
import pandas as pd

def run_cmd(cmd):
    start = time.time()
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    end = time.time()
    return end - start, res.stdout

def verify():
    bin_time, bin_out = run_cmd("/app/legacy_aggregator /tmp/eval_telemetry.log")
    with open('/tmp/bin_out.csv', 'w') as f:
        f.write(bin_out)

    py_time, py_out = run_cmd("python3 /home/user/fast_aggregator.py /tmp/eval_telemetry.log /tmp/py_out.csv")

    speedup = bin_time / py_time if py_time > 0 else 0

    try:
        df_bin = pd.read_csv('/tmp/bin_out.csv')
        df_py = pd.read_csv('/tmp/py_out.csv')
        pd.testing.assert_frame_equal(df_bin, df_py, check_exact=False, atol=1e-4)
        accuracy = 1.0
    except Exception as e:
        accuracy = 0.0

    if speedup >= 20.0 and accuracy == 1.0:
        print("100.0")
    else:
        print("0.0")

if __name__ == '__main__':
    verify()
EOF

    chmod -R 777 /home/user
