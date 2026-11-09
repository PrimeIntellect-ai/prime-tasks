#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup script to create the environment and input files
    mkdir -p /home/user/inputs

    # Create mem_metrics.json
    cat << 'EOF' > /home/user/inputs/mem_metrics.json
[
  {"ts": 1622505600, "srv_alpha": 45.0, "srv_beta": 92.5, "srv_gamma": 30.0},
  {"ts": 1622505660, "srv_alpha": 50.0, "srv_beta": 89.0, "srv_gamma": 95.2},
  {"ts": 1622505720, "srv_alpha": 91.0, "srv_beta": 60.0, "srv_gamma": 50.0}
]
EOF

    # Create cpu_metrics.csv in UTF-8 first, then convert to UTF-16LE
    cat << 'EOF' > /home/user/inputs/cpu_metrics_utf8.csv
timestamp,srv_alpha,srv_beta,srv_gamma
1622505600,40.0,86.5,20.0
1622505660,88.1,40.0,30.0
1622505720,40.0,50.0,87.0
EOF

    iconv -f UTF-8 -t UTF-16LE /home/user/inputs/cpu_metrics_utf8.csv > /home/user/inputs/cpu_metrics.csv
    rm /home/user/inputs/cpu_metrics_utf8.csv

    # Expected canonical anomalies.jsonl contents
    mkdir -p /home/user/expected_output
    cat << 'EOF' > /home/user/expected_output/anomalies.jsonl
{"timestamp": 1622505600, "server": "srv_beta", "metric": "cpu", "value": 86.5}
{"timestamp": 1622505600, "server": "srv_beta", "metric": "mem", "value": 92.5}
{"timestamp": 1622505660, "server": "srv_alpha", "metric": "cpu", "value": 88.1}
{"timestamp": 1622505660, "server": "srv_gamma", "metric": "mem", "value": 95.2}
{"timestamp": 1622505720, "server": "srv_alpha", "metric": "mem", "value": 91.0}
{"timestamp": 1622505720, "server": "srv_gamma", "metric": "cpu", "value": 87.0}
EOF

    # Verification script
    cat << 'EOF' > /tmp/verify.sh
#!/bin/bash
if [ ! -f /home/user/output/anomalies.jsonl ]; then
    echo "Output file missing"
    exit 1
fi

# Compare the generated output with the expected output, ignoring whitespace
diff -wB /home/user/output/anomalies.jsonl /home/user/expected_output/anomalies.jsonl > /dev/null
if [ $? -eq 0 ]; then
    echo "Success"
    exit 0
else
    echo "Output mismatch"
    exit 1
fi
EOF
    chmod +x /tmp/verify.sh

    # Set permissions
    chmod -R 777 /home/user
