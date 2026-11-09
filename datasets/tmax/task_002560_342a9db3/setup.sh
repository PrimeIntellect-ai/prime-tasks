#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/backup_data/app1
    mkdir -p /home/user/backup_data/app2
    touch /home/user/backup_data/app1/config.json
    touch /home/user/backup_data/app1/data.db
    touch /home/user/backup_data/app2/cache.bin

    cat << 'EOF' > /home/user/user_backup.fstab
/home/user/backup_data/app1 /home/user/restore/app1 none bind 0 0
/home/user/backup_data/app2 /home/user/restore/app2 none bind 0 0
/home/user/backup_data/missing /home/user/restore/missing none bind 0 0
EOF

    cat << 'EOF' > /home/user/mock_container.py
import sys
import time

def main():
    dirs = sys.argv[1:]
    print(f"Starting mock container for dirs: {dirs}")
    counter = 0
    try:
        while True:
            # Generate a lot of output to trigger log rotation
            print(f"Log line {counter}: Processing data from restored directories. " * 5)
            counter += 1
            time.sleep(0.05)
    except KeyboardInterrupt:
        print("Received shutdown signal. Exiting clean.")
        sys.exit(0)

if __name__ == "__main__":
    # Handle SIGTERM same as KeyboardInterrupt
    import signal
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    main()
EOF

    chmod +x /home/user/mock_container.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
