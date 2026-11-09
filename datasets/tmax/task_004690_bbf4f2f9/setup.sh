#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils git
    pip3 install pytest

    mkdir -p /app /home/user/wrapper_repo

    # Create C source for record_engine
    cat << 'EOF' > /tmp/engine.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    char *fast_mode = getenv("ENGINE_FAST_MODE");
    int fast = (fast_mode && fast_mode[0] == '1');

    int len;
    while (fread(&len, sizeof(int), 1, stdin) == 1) {
        if (len <= 0 || len > 1000000) break;
        char *buf = malloc(len);
        if (fread(buf, 1, len, stdin) != len) {
            free(buf);
            break;
        }
        for (int i = 0; i < len; i++) {
            if ((unsigned char)buf[i] == 0xFF) {
                abort();
            }
        }
        free(buf);
        if (!fast) {
            usleep(1000); // 1ms delay per record
        }
    }
    return 0;
}
EOF

    gcc -O2 /tmp/engine.c -o /app/record_engine
    strip /app/record_engine

    # Create eval_data.json
    python3 -c '
import json
data = ["hello world" for _ in range(4990)]
data.extend(["hello world \u2022" for _ in range(10)])
with open("/app/eval_data.json", "w") as f:
    json.dump(data, f)
'

    # Create good driver
    cat << 'EOF' > /tmp/good_driver.py
import sys
import json
import struct
import subprocess
import os
import time

os.environ["ENGINE_FAST_MODE"] = "1"

def process(data_path):
    with open(data_path, 'r') as f:
        records = json.load(f)

    start = time.time()
    p = subprocess.Popen(["/app/record_engine"], stdin=subprocess.PIPE)
    for r in records:
        b = r.encode('utf-8')
        p.stdin.write(struct.pack('i', len(b)))
        p.stdin.write(b)
    p.stdin.close()
    p.wait()
    end = time.time()

    with open("/home/user/metrics.log", "w") as f:
        f.write(str(end - start))

if __name__ == "__main__":
    process(sys.argv[1])
EOF

    # Create bad driver
    cat << 'EOF' > /tmp/bad_driver.py
import sys
import json
import struct
import subprocess
import os
import time

# Custom encoder for performance (buggy)
def str_to_bytes(s):
    res = bytearray()
    for c in s:
        val = ord(c)
        if val > 127:
            res.append(0xFF) # Bug!
        else:
            res.append(val)
    return bytes(res)

def process(data_path):
    with open(data_path, 'r') as f:
        records = json.load(f)

    start = time.time()
    p = subprocess.Popen(["/app/record_engine"], stdin=subprocess.PIPE)
    for r in records:
        b = str_to_bytes(r)
        p.stdin.write(struct.pack('i', len(b)))
        p.stdin.write(b)
    p.stdin.close()
    p.wait()
    end = time.time()

    with open("/home/user/metrics.log", "w") as f:
        f.write(str(end - start))

if __name__ == "__main__":
    process(sys.argv[1])
EOF

    # Setup git repo
    cd /home/user/wrapper_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    for i in $(seq 1 5); do
        echo "commit $i" > file.txt
        git add file.txt
        git commit -m "Initial commit $i"
    done

    cp /tmp/good_driver.py driver.py
    git add driver.py
    git commit -m "Add initial driver implementation"

    for i in $(seq 6 10); do
        echo "commit $i" > file.txt
        git add file.txt
        git commit -m "Misc update $i"
    done

    cp /tmp/bad_driver.py driver.py
    git add driver.py
    git commit -m "Optimize driver encoding and remove debug flags"

    for i in $(seq 11 13); do
        echo "commit $i" > file.txt
        git add file.txt
        git commit -m "Post optimization update $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
