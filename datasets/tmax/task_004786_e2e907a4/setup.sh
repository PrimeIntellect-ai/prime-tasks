#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# Ground truth events to encode
events = """1000 SET A 10
1000 SET B 20
1001 UPDATE A 15
1001 DELETE B X
1002 SET C 30
"""
# pad to multiple of 3
while len(events) % 3 != 0:
    events += " "

frames = []
for i in range(0, len(events), 3):
    r, g, b = ord(events[i]), ord(events[i+1]), ord(events[i+2])
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    frame[0, 0] = [b, g, r] # OpenCV uses BGR
    frames.append(frame)

# pad video to 5 seconds at 10 fps (50 frames total)
while len(frames) < 50:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    frame[0, 0] = [32, 32, 32] # spaces
    frames.append(frame)

out = cv2.VideoWriter('/app/dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for f in frames:
    out.write(f)
out.release()
EOF
    python3 /tmp/gen_video.py

    cat << 'EOF' > /app/oracle_tracker.py
import sys
from collections import defaultdict

def run():
    state = {}
    events_by_ts = defaultdict(list)

    for line in sys.stdin:
        parts = line.strip().split()
        if len(parts) != 4:
            continue
        ts_str, op, key, val = parts
        try:
            ts = int(ts_str)
            if ts < 0: continue
        except ValueError:
            continue

        if not key.replace('_', '').isalnum():
            continue

        events_by_ts[ts].append((op, key, val))

    for ts in sorted(events_by_ts.keys()):
        # Deduplicate: keep last operation per key
        key_ops = {}
        for op, key, val in events_by_ts[ts]:
            key_ops[key] = (op, val)

        changed = False
        for key, (op, val) in key_ops.items():
            if op == 'SET':
                if state.get(key) != val:
                    state[key] = val
                    changed = True
            elif op == 'UPDATE':
                if key in state and state[key] != val:
                    state[key] = val
                    changed = True
            elif op == 'DELETE':
                if key in state:
                    del state[key]
                    changed = True

        if changed:
            if not state:
                print(f"{ts} => EMPTY")
            else:
                formatted = ", ".join(f"{k}={state[k]}" for k in sorted(state.keys()))
                print(f"{ts} => {formatted}")

if __name__ == '__main__':
    run()
EOF
    chmod +x /app/oracle_tracker.py

    cat << 'EOF' > /app/oracle_tracker
#!/bin/bash
python3 /app/oracle_tracker.py
EOF
    chmod +x /app/oracle_tracker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
