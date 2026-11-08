#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

# Create SQLite DB and populate with mock SRE data
sqlite3 /home/user/uptime.db <<EOF
CREATE TABLE incidents (
    id INTEGER PRIMARY KEY,
    start_time INTEGER,
    end_time INTEGER,
    severity INTEGER
);
INSERT INTO incidents (start_time, end_time, severity) VALUES (1000, 1150, 2); -- Valid: Duration 150, sev 2 -> 60
INSERT INTO incidents (start_time, end_time, severity) VALUES (2000, 2120, 3); -- Valid: Duration 120, sev 3 -> 60
INSERT INTO incidents (start_time, end_time, severity) VALUES (3000, 2900, 1); -- Invalid: end < start
INSERT INTO incidents (start_time, end_time, severity) VALUES (4000, 4050, 0); -- Invalid: Maintenance (sev 0)
EOF

# Create the buggy Python script
cat << 'EOF' > /home/user/calculate_sla.py
import sqlite3
import sys

# Increase recursion depth slightly to ensure the buggy version fails predictably
sys.setrecursionlimit(1000)

def compute_cascade_penalty(duration, severity):
    # BUG: strict equality causes infinite recursion for durations not exactly divisible by 60
    if duration == 0:
        return 0
    return (severity * 10) + compute_cascade_penalty(duration - 60, severity)

def calculate_total_penalty():
    conn = sqlite3.connect('/home/user/uptime.db')
    c = conn.cursor()

    # BUG: Fetches invalid rows and maintenance windows
    c.execute("SELECT start_time, end_time, severity FROM incidents")
    incidents = c.fetchall()

    total = 0
    for start, end, sev in incidents:
        # Assertion-based validation
        assert end >= start, f"Data anomaly: end_time {end} is before start_time {start}"
        assert sev > 0, f"Data anomaly: Maintenance window (severity 0) included!"

        duration = end - start
        total += compute_cascade_penalty(duration, sev)

    return total

if __name__ == "__main__":
    ans = calculate_total_penalty()
    with open("/home/user/sla_penalty_result.txt", "w") as f:
        f.write(str(ans))
EOF

chmod +x /home/user/calculate_sla.py
chmod -R 777 /home/user
