#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/ping_logs.json
{
  "service_a": {"total_time_minutes": 1440, "downtime_minutes": 15},
  "service_b": {"total_time_minutes": 1440, "downtime_minutes": 0},
  "service_c": {"total_time_minutes": 1440, "downtime_minutes": 120}
}
EOF

    mkdir -p /home/user/uptime_monitor
    cd /home/user/uptime_monitor

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init

    # Initial good commit
    cat << 'EOF' > monitor.py
import json
import argparse

def calculate_sla(total_time, downtime):
    return (total_time - downtime) / total_time * 100.0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--logs', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    with open(args.logs, 'r') as f:
        data = json.load(f)

    report = {}
    for svc, metrics in data.items():
        report[svc] = calculate_sla(metrics['total_time_minutes'], metrics['downtime_minutes'])

    with open(args.output, 'w') as f:
        json.dump(report, f, indent=2)

if __name__ == '__main__':
    main()
EOF
    cat << 'EOF' > requirements.txt
argparse
EOF
    git add monitor.py requirements.txt
    git commit -m "Initial commit with working SLA calculator"
    git tag v1.0-stable

    # Create some dummy commits
    for i in {1..5}; do
        echo "# dummy $i" >> monitor.py
        git commit -am "Refactor: clean up code part $i"
    done

    # Introduce the formula bug
    cat << 'EOF' > monitor.py
import json
import argparse

def calculate_sla(total_time, downtime):
    # BUG: addition instead of subtraction
    return (total_time + downtime) / total_time * 100.0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--logs', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    with open(args.logs, 'r') as f:
        data = json.load(f)

    report = {}
    for svc, metrics in data.items():
        report[svc] = calculate_sla(metrics['total_time_minutes'], metrics['downtime_minutes'])

    with open(args.output, 'w') as f:
        json.dump(report, f, indent=2)

if __name__ == '__main__':
    main()
EOF
    git commit -am "Update SLA calculation logic to handle edge cases"
    BAD_COMMIT=$(git rev-parse HEAD)
    echo $BAD_COMMIT > /tmp/expected_bad_commit.txt

    # Create more dummy commits
    for i in {6..9}; do
        echo "# dummy $i" >> monitor.py
        git commit -am "Refactor: clean up code part $i"
    done

    # Introduce environment misconfiguration
    cat << 'EOF' > requirements.txt
argparse
reqeusts==2.31.0
EOF
    sed -i '1s/^/import os\nimport reqeusts  # broken import\n/' monitor.py
    git commit -am "Add requests dependency for future webhook integration"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/uptime_monitor
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
