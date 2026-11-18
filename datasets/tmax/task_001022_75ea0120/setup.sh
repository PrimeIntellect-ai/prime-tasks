#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

mkdir -p /home/user/incident_triage
cd /home/user/incident_triage

cat << 'EOF' > requirements.txt
Jinja2==2.11.3
EOF

cat << 'EOF' > processor.py
import json
import sys
import argparse

def process_job(payload_path):
    with open(payload_path, 'r') as f:
        payload = json.load(f)

    print(f"Processing job {payload.get('job_id')}")

    if payload.get("send_email"):
        # Lazy import of notifier to simulate intermittent triggering
        import notifier
        notifier.send_notification(payload.get("user_email"), "Job Complete")

    print("Job processed successfully.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", required=True)
    args = parser.parse_args()
    process_job(args.payload)
EOF

cat << 'EOF' > notifier.py
import jinja2

def send_notification(email, message):
    template = jinja2.Template("Hello " + chr(123)*2 + " email " + chr(125)*2 + ", message: " + chr(123)*2 + " message " + chr(125)*2)
    rendered = template.render(email=email, message=message)
    print(f"Email sent to {email}")
EOF

# Generate logs
cat << 'EOF' > container_logs.log
{"timestamp": "2023-10-25T10:00:01Z", "level": "INFO", "msg": "Starting job", "job_id": 1001, "payload": {"job_id": 1001, "data": "alpha", "send_email": false}}
{"timestamp": "2023-10-25T10:00:02Z", "level": "INFO", "msg": "Job processed successfully", "job_id": 1001}
{"timestamp": "2023-10-25T10:00:05Z", "level": "INFO", "msg": "Starting job", "job_id": 1002, "payload": {"job_id": 1002, "data": "beta", "send_email": false}}
{"timestamp": "2023-10-25T10:00:06Z", "level": "INFO", "msg": "Job processed successfully", "job_id": 1002}
{"timestamp": "2023-10-25T10:00:10Z", "level": "INFO", "msg": "Starting job", "job_id": 1003, "payload": {"job_id": 1003, "data": "gamma", "send_email": true, "user_email": "admin@example.com"}}
{"timestamp": "2023-10-25T10:00:11Z", "level": "ERROR", "msg": "Worker process crashed unexpectedly with exit code 1", "job_id": 1003}
{"timestamp": "2023-10-25T10:00:15Z", "level": "INFO", "msg": "Starting job", "job_id": 1004, "payload": {"job_id": 1004, "data": "delta", "send_email": false}}
{"timestamp": "2023-10-25T10:00:16Z", "level": "INFO", "msg": "Job processed successfully", "job_id": 1004}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
