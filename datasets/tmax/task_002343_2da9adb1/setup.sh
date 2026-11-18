#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create repo
    mkdir -p /home/user/sync_service
    cd /home/user/sync_service
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Good code
    cat << 'EOF' > main.py
import threading
import time

lock1 = threading.Lock()
lock2 = threading.Lock()

def worker1():
    with lock1:
        time.sleep(0.05)
        with lock2:
            pass

def worker2():
    with lock1:
        time.sleep(0.05)
        with lock2:
            pass

if __name__ == "__main__":
    t1 = threading.Thread(target=worker1)
    t2 = threading.Thread(target=worker2)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
EOF

    git add main.py
    git commit -m "Initial commit"
    git tag v1.0

    # Generate 120 good commits
    for i in $(seq 1 120); do
        echo "# Good commit $i" >> main.py
        git commit -am "Refactor sync logic $i"
    done

    # Bad code (Deadlock)
    cat << 'EOF' > main.py
import threading
import time

lock1 = threading.Lock()
lock2 = threading.Lock()

def worker1():
    with lock1:
        time.sleep(0.05)
        with lock2:
            pass

def worker2():
    with lock2:
        time.sleep(0.05)
        with lock1:
            pass

if __name__ == "__main__":
    t1 = threading.Thread(target=worker1)
    t2 = threading.Thread(target=worker2)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
EOF

    git commit -am "Optimize lock acquisition order"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Generate 79 more bad commits
    for i in $(seq 1 79); do
        echo "# Bad commit $i" >> main.py
        git commit -am "Update dependencies $i"
    done
    git tag v2.0

    # Create dummy memory dump
    dd if=/dev/urandom of=/home/user/core.dmp bs=1M count=2 2>/dev/null
    echo "SOME_OTHER_DATA_SECRET_TOKEN-X9aB2vP4mL6qR1wZ_MORE_DATA" >> /home/user/core.dmp
    dd if=/dev/urandom bs=1M count=1 2>/dev/null >> /home/user/core.dmp

    # Save the expected answers to a secure location for verification
    mkdir -p /tmp/verification
    echo "$BAD_COMMIT" > /tmp/verification/bad_commit.txt
    echo "SECRET_TOKEN-X9aB2vP4mL6qR1wZ" > /tmp/verification/token.txt

    chmod -R 777 /home/user
    chmod -R 777 /tmp/verification
