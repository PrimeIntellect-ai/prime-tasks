#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip locales
    pip3 install pytest

    # Generate the locale needed for the bug to manifest properly
    locale-gen fr_FR.UTF-8

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_logs.py
import random

lines = []
# Ensure a specific set of 500/502 errors for the baseline calculation
# Mean response time ~ 1000.0, to trigger catastrophic cancellation in standard sum_sq/N - (sum/N)^2
# if not careful.
base_times = [1000.01, 1000.02, 1000.01, 1000.03, 1000.02, 1000.01, 1000.02, 1000.03]
for t in base_times:
    lines.append(f'192.168.1.1 - - [10/Oct/2023:13:55:36 -0700] "POST /api/v1/process HTTP/1.1" 500 1234 {t}')

lines.append(f'192.168.1.2 - - [10/Oct/2023:13:56:36 -0700] "POST /api/v1/process HTTP/2.0" 502 1234 1000.05')

# Anomalies (Should be picked up because mean is ~1000.02, stddev is ~0.01, threshold is ~1000.04)
# Wait, for the above 9 items:
# values: 1000.01 (x3), 1000.02 (x3), 1000.03 (x2), 1000.05 (x1)
# mean: 9000.18 / 9 = 1000.02
# Anomaly threshold: mean + 2*stddev.
# Values are so tightly clustered that an unstable one-pass variance might yield negative.
lines.append(f'10.0.0.1 - - [10/Oct/2023:14:00:00 -0700] "POST /api/v1/process HTTP/1.1" 200 1024 1000.06') # Anomaly
lines.append(f'10.0.0.2 - - [10/Oct/2023:14:01:00 -0700] "POST /api/v1/process HTTP/1.1" 200 1024 1000.07') # Anomaly
lines.append(f'10.0.0.3 - - [10/Oct/2023:14:02:00 -0700] "POST /api/v1/process HTTP/1.1" 200 1024 999.00') # Not anomaly

with open("/home/user/access.log", "w") as f:
    for line in lines:
        f.write(line + "\n")
EOF
    python3 /home/user/generate_logs.py

    cat << 'EOF' > /home/user/analyze_logs.sh
#!/bin/bash
export LC_NUMERIC="fr_FR.UTF-8" # Bug 1: Environment misconfiguration causing comma decimals

# Bug 3: Missing HTTP/2.0 and 502
# Bug 4: No intermediate tracing written to debug_counts.txt
FILTERED=$(grep "/api/v1/process HTTP/1.1\" 500" /home/user/access.log)

# Extract response times and compute threshold
THRESHOLD=$(echo "$FILTERED" | awk '
{
    val = $NF
    sum += val
    sum_sq += val * val
    count++
}
END {
    mean = sum / count
    # Bug 2: Numerical instability
    var = (sum_sq / count) - (mean * mean)
    stddev = sqrt(var)
    print mean + 2 * stddev
}')

grep "/api/v1/process" /home/user/access.log | awk -v thresh="$THRESHOLD" '{if ($NF > thresh) print $0}' > /home/user/anomalies.log
EOF
    chmod +x /home/user/analyze_logs.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
