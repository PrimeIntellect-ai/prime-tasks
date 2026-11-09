#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > "/home/user/data/dataset 1.csv"
100000000.1
100000000.2
100000000.3
EOF

    cat << 'EOF' > "/home/user/data/dataset 2.csv"
2.0
4.0
4.0
4.5
EOF

    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
rm -f /home/user/results.txt
# BUG: breaks on spaces in filenames
for f in $(ls /home/user/data/*.csv); do
    python3 /home/user/process.py $f >> /home/user/results.txt
done
EOF
    chmod +x /home/user/pipeline.sh

    cat << 'EOF' > /home/user/process.py
import sys
import csv

def calc_variance(file_path):
    with open(file_path, 'r') as f:
        reader = csv.reader(f)
        data = [float(row[0]) for row in reader]

    n = len(data)
    if n < 2:
        return 0.0

    # Naive variance calculation (susceptible to catastrophic cancellation)
    sum_x = sum(data)
    sum_x2 = sum(x**2 for x in data)

    variance = (sum_x2 - (sum_x**2) / n) / (n - 1)

    assert variance >= 0, f"AssertionError: Negative variance detected ({variance}) due to numerical instability!"
    return variance

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    f = sys.argv[1]
    var = calc_variance(f)
    print(f"{f}: {var}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
