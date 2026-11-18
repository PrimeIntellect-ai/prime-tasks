#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/build.py
import os
import time
import threading
import json
from datetime import datetime

def generate_manifest():
    data = {"version": "1.0.42", "timestamp": datetime.now().isoformat()}
    with open("manifest.tmp", "w") as f:
        json.dump(data, f)
    # Simulate time-consuming build preparation
    time.sleep(1)

def cleanup_old_builds():
    # Wait briefly to ensure manifest is created before checking
    time.sleep(0.2)
    if os.path.exists("manifest.tmp"):
        # BUG: Mixing naive local time from fromtimestamp() with utcnow().
        # Because the TZ is set to America/New_York (UTC-5), utcnow() is 5 hours ahead of local time.
        # This makes the newly created file appear to be 5 hours old, triggering immediate deletion.
        file_time = datetime.fromtimestamp(os.path.getmtime("manifest.tmp"))
        now_utc = datetime.utcnow()
        diff = (now_utc - file_time).total_seconds()

        # If the file appears older than 1 hour, clean it up
        if diff > 3600:
            os.remove("manifest.tmp")

def main():
    # Force system timezone to EST to guarantee the bug triggers
    os.environ['TZ'] = 'America/New_York'
    time.tzset()

    # Change to project directory to ensure relative paths work
    os.chdir("/home/user/project")

    t1 = threading.Thread(target=generate_manifest)
    t2 = threading.Thread(target=cleanup_old_builds)

    t1.start()
    t2.start()

    t1.join()
    t2.join()

    # Build step - consumes the manifest
    with open("manifest.tmp", "r") as f:
        data = json.load(f)

    with open("build_artifact.txt", "w") as f:
        f.write(f"SUCCESS: {data['version']}")

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/project/build.py
    chmod -R 777 /home/user
