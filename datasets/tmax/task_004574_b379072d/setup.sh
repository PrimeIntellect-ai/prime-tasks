#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest SpeechRecognition

    mkdir -p /app
    espeak -w /app/experiment_parameters.wav "The weights are three point five, zero point two, one point eight, and four point zero."

    cat << 'EOF' > /app/oracle_process_features.py
#!/usr/bin/env python3
import sys
import csv

def main():
    reader = csv.DictReader(sys.stdin)
    fieldnames = ['A', 'B', 'C', 'D', 'weighted_sum', 'interaction']
    writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
    writer.writeheader()
    for row in reader:
        a, b, c, d = float(row['A']), float(row['B']), float(row['C']), float(row['D'])
        w_sum = 3.5 * a + 0.2 * b + 1.8 * c + 4.0 * d
        inter = (a * b) - (c * d)
        row['weighted_sum'] = f"{w_sum:.4f}"
        row['interaction'] = f"{inter:.4f}"
        writer.writerow(row)

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/oracle_process_features.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
