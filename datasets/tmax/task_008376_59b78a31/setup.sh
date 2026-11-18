#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/ticket_8492

    cat << 'EOF' > /home/user/ticket_8492/data.csv
1,2023-01-01,Init system,15
2,2023-01-02,Load config,25
3,2023-01-03,"Warning, missing config file",50
4,2023-01-04,Process started,10
EOF

    cat << 'EOF' > /home/user/ticket_8492/process_logs.py
import threading
import queue

def process_line(line):
    # Extracts the value from the 4th column (index 3)
    parts = line.strip().split(',')
    val = int(parts[3])
    return val

def worker(in_q, out_q):
    while True:
        item = in_q.get()
        if item is None:
            break
        idx, line = item
        try:
            res = process_line(line)
            out_q.put(res)
        except Exception:
            # Drop the result if processing fails
            pass
        in_q.task_done()

def main():
    with open('/home/user/ticket_8492/data.csv', 'r') as f:
        lines = f.readlines()

    in_q = queue.Queue()
    out_q = queue.Queue()

    threads = []
    for _ in range(4):
        t = threading.Thread(target=worker, args=(in_q, out_q))
        t.start()
        threads.append(t)

    for i, line in enumerate(lines):
        if line.strip():
            in_q.put((i, line))

    # Signal workers to exit
    for _ in range(4):
        in_q.put(None)

    total_val = 0
    # Wait for results
    for _ in range(len(lines) + 1):
        total_val += out_q.get()

    for t in threads:
        t.join()

    with open('/home/user/ticket_8492/output.txt', 'w') as f:
        f.write(str(total_val))

if __name__ == '__main__':
    main()
EOF

    chmod +x /home/user/ticket_8492/process_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
