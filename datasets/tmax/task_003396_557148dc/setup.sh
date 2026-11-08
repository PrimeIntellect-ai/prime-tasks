#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jinja2

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import datetime
from datetime import timedelta

os.makedirs("/home/user", exist_ok=True)

logs = []
base_time = datetime.datetime(2023, 10, 25, 10, 0, 0)

# Normal logs (UTF-8)
logs.append((base_time, "JOB100", "Starting extraction...", "utf-8"))
logs.append((base_time + timedelta(minutes=1), "JOB100", "Extraction complete.", "utf-8"))

# Bursty logs (Latin-1 mixed)
# JOB200 has a burst of 5 identical messages in 3 minutes
t = base_time + timedelta(minutes=10)
for i in range(5):
    logs.append((t + timedelta(seconds=i*30), "JOB200", "Error: Connection reset by peer!", "latin-1" if i%2==0 else "utf-8"))

# JOB300 has identical messages but spread over 20 minutes (no burst)
t = base_time + timedelta(minutes=20)
for i in range(5):
    logs.append((t + timedelta(minutes=i*4), "JOB300", "Timeout waiting for lock.", "utf-8"))

# JOB400 has a burst of 4 messages in 4 minutes
t = base_time + timedelta(minutes=50)
for i in range(4):
    logs.append((t + timedelta(minutes=i*1), "JOB400", "Retrying... (attempt)", "latin-1"))

with open("/home/user/raw_etl.log", "wb") as f:
    for dt, jid, msg, enc in logs:
        line = f"[{dt.strftime('%Y-%m-%d %H:%M:%S')}] | JobID:{jid} | {msg}\n"
        f.write(line.encode(enc))

t_open = chr(123) * 2
t_close = chr(125) * 2
p_open = chr(123) + "%"
p_close = "%" + chr(125)

template = f"""# Retry Burst Report

The following jobs experienced retry bursts (>=4 identical messages in 5 mins):

{p_open} for job in jobs {p_close}
* Job {t_open} job.job_id {t_close}: max burst size of {t_open} job.max_burst_size {t_close}
{p_open} endfor {p_close}
"""

with open("/home/user/report_template.md", "w") as f:
    f.write(template)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
