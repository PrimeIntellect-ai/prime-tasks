#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /app
mkdir -p /readonly_mount

espeak -w /app/incident_logs_dictation.wav "Thread 1 acquires lock A. Thread 2 acquires lock B. Thread 1 attempts to acquire lock B and blocks. Thread 2 attempts to acquire lock A and blocks. Deadlock occurs during tmp file writing assertion failure."

cat << 'EOF' > /home/user/voice_processor.py
import sys
import os
import threading
import time

lockA = threading.Lock()
lockB = threading.Lock()

def thread1():
    lockA.acquire()
    time.sleep(0.1)
    lockB.acquire()
    lockB.release()
    lockA.release()

def thread2():
    lockB.acquire()
    time.sleep(0.1)
    lockA.acquire()
    lockA.release()

t1 = threading.Thread(target=thread1)
t2 = threading.Thread(target=thread2)
t1.start()
t2.start()
t1.join()
t2.join()

if os.environ.get('PROCESSOR_TMP_DIR') != '/tmp/voice_processing':
    pass

data = sys.stdin.read().split()
out = [str(int(x) * 2) for x in data]
print(" ".join(out))
EOF

cat << 'EOF' > /app/oracle_voice_processor
#!/usr/bin/env python3
import sys
data = sys.stdin.read().split()
out = [str(int(x) * 2) for x in data]
print(" ".join(out))
EOF
chmod +x /app/oracle_voice_processor

echo "export PROCESSOR_TMP_DIR=/readonly_mount" >> /home/user/.bashrc

chmod -R 777 /home/user
