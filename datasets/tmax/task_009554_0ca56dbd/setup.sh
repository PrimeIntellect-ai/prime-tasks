#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/ticket_4092

    cat << 'EOF' > /home/user/ticket_4092/process_jobs.py
import threading

counter = 0

def process_job():
    global counter
    for _ in range(100000):
        # Race condition here
        v = counter
        counter = v + 1

def main():
    threads = []
    for _ in range(10):
        t = threading.Thread(target=process_job)
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    print(counter)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
