#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app/data
    cd /home/user/app

    # Create the buggy script
    cat << 'EOF' > process_logs.py
import json
import sys

def process_line(data):
    # Bug 1: Strict string comparison for status
    status = data.get("status")

    # Crash Condition 1: ValueError
    if "api/v1/legacy" in data.get("endpoint", ""):
        if "user_agent" not in data:
            raise ValueError("FATAL: Legacy endpoint requires user_agent")

    # Crash Condition 2: Hidden bug to find via fuzzing
    if data.get("method") == "POST" and type(data.get("payload_size")) in (int, float):
        if data.get("payload_size") > 10000:
            raise MemoryError("Payload too large")

    return {
        "is_500": status == "500",
        "endpoint": data.get("endpoint", "")
    }

def main():
    summary = {"500_count": 0, "legacy_hits": 0}
    try:
        with open("data/system.log") as f:
            for line in f:
                data = json.loads(line)
                res = process_line(data)

                if res["is_500"]:
                    summary["500_count"] += 1
                if "api/v1/legacy" in res["endpoint"]:
                    summary["legacy_hits"] += 1

        with open("final_summary.json", "w") as f:
            json.dump(summary, f)

    except Exception as e:
        print(f"Unhandled exception: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    # Create the log data
    cat << 'EOF' > data/system.log
{"status": 200, "endpoint": "api/v2/users", "method": "GET", "user_agent": "test"}
{"status": "500", "endpoint": "api/v2/data", "method": "GET", "user_agent": "test"}
{"status": 500, "endpoint": "api/v2/data", "method": "GET", "user_agent": "test"}
{"status": "500", "endpoint": "api/v2/data", "method": "GET", "user_agent": "test"}
{"status": 500, "endpoint": "api/v2/data", "method": "GET", "user_agent": "test"}
{"status": 200, "endpoint": "api/v1/legacy", "method": "GET"}
{"status": 200, "endpoint": "api/v2/users", "method": "POST", "payload_size": 15000, "user_agent": "test"}
{"status": "500", "endpoint": "api/v1/legacy", "method": "GET", "user_agent": "test"}
{"status": 500, "endpoint": "api/v1/legacy", "method": "GET", "user_agent": "test"}
EOF

    # Create the app.log to simulate previous crash
    cat << 'EOF' > app.log
Traceback (most recent call last):
  File "/home/user/app/process_logs.py", line 43, in <module>
    main()
  File "/home/user/app/process_logs.py", line 29, in main
    res = process_line(data)
  File "/home/user/app/process_logs.py", line 11, in process_line
    raise ValueError("FATAL: Legacy endpoint requires user_agent")
ValueError: FATAL: Legacy endpoint requires user_agent
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
