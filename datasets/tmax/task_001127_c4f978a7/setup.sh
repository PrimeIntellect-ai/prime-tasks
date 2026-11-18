#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler libglib2.0-0
    pip3 install pytest protobuf numpy opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user

    # Create the video generation script
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

base_deps = [
    (10, 20), (20, 30), (5, 15), (15, 25), (30, 40),
    (2, 4), (4, 8), (8, 16), (3, 6), (6, 12)
]

width, height = 320, 240
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/protocol_dump.mp4', fourcc, 1.0, (width, height))

for u, v in base_deps:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    frame[:height//2, :, :] = u
    frame[height//2:, :, :] = v
    out.write(frame)

out.release()
EOF

    python3 /app/generate_video.py
    rm /app/generate_video.py

    # Create the reference oracle
    cat << 'EOF' > /app/reference_oracle.py
import sys
import job_pb2

def main():
    base_deps = [
        (10, 20), (20, 30), (5, 15), (15, 25), (30, 40),
        (2, 4), (4, 8), (8, 16), (3, 6), (6, 12)
    ]

    deps = {u: set() for u, v in base_deps}
    for u, v in base_deps:
        if v not in deps: deps[v] = set()
        deps[v].add(u)

    executed = set()
    pending = set()
    log = []

    with open(sys.argv[1], "rb") as f:
        prog = job_pb2.Program()
        prog.ParseFromString(f.read())

    for inst in prog.instructions:
        if inst.op == job_pb2.Instruction.ADD_JOB:
            pending.add(inst.u)
        elif inst.op == job_pb2.Instruction.ADD_DEP:
            if inst.v not in deps: deps[inst.v] = set()
            deps[inst.v].add(inst.u)
        elif inst.op == job_pb2.Instruction.EXECUTE:
            ready = []
            for job in pending:
                job_deps = deps.get(job, set())
                if job_deps.issubset(executed):
                    ready.append(job)
            ready.sort()
            for job in ready:
                pending.remove(job)
                executed.add(job)
                log.append(job)

    print(",".join(map(str, log)))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
