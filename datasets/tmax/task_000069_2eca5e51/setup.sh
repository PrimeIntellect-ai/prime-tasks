#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv g++ nlohmann-json3-dev
    pip3 install pytest numpy

    # Create setup script to generate video and corpus
    cat << 'EOF' > /tmp/setup.py
import os
import json
import cv2
import numpy as np
import math

os.makedirs("/app", exist_ok=True)
out = cv2.VideoWriter('/app/experiment.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
for _ in range(60):
    out.write(np.ones((100, 100, 3), dtype=np.uint8) * 255)
for _ in range(90):
    out.write(np.zeros((100, 100, 3), dtype=np.uint8))
out.release()

os.makedirs("/app/corpus/clean", exist_ok=True)
for i in range(5):
    succ = 40 + i
    fail = 100 + i
    a = 1.0
    b = 1.0
    ap = a + succ
    bp = b + fail
    pm = ap / (ap + bp)
    pv = (ap * bp) / (((ap + bp)**2) * (ap + bp + 1))
    d = {"experiment_id": f"exp_clean_{i}", "successes": succ, "failures": fail, "prior_alpha": a, "prior_beta": b, "posterior_mean": pm, "posterior_variance": pv}
    with open(f"/app/corpus/clean/clean_{i}.json", "w") as f:
        json.dump(d, f)

os.makedirs("/app/corpus/evil", exist_ok=True)
def write_evil(i, d):
    with open(f"/app/corpus/evil/evil_{i}.json", "w") as f:
        json.dump(d, f)

d1 = {"experiment_id": "e1", "successes": -5, "failures": 100, "prior_alpha": 1.0, "prior_beta": 1.0, "posterior_mean": 0.5, "posterior_variance": 0.1}
write_evil(0, d1)
write_evil(1, d1)

d2 = {"experiment_id": "e2", "successes": 50, "failures": 100, "prior_alpha": 0.0, "prior_beta": 1.0, "posterior_mean": 0.5, "posterior_variance": 0.1}
write_evil(2, d2)
write_evil(3, d2)

succ = 50; fail = 100; a = 1.0; b = 1.0; ap = a + succ; bp = b + fail
pm = ap / (ap + bp) + 0.01
pv = (ap * bp) / (((ap + bp)**2) * (ap + bp + 1))
d3 = {"experiment_id": "e3", "successes": succ, "failures": fail, "prior_alpha": a, "prior_beta": b, "posterior_mean": pm, "posterior_variance": pv}
write_evil(4, d3)
write_evil(5, d3)
write_evil(6, d3)

pv_bad = (ap * bp) / (((ap + bp)**2) * (ap + bp))
d4 = {"experiment_id": "e4", "successes": succ, "failures": fail, "prior_alpha": a, "prior_beta": b, "posterior_mean": ap/(ap+bp), "posterior_variance": pv_bad}
write_evil(7, d4)
write_evil(8, d4)

d5 = {"experiment_id": "e5", "successes": succ, "failures": fail, "prior_alpha": a, "prior_beta": b, "posterior_mean": math.nan, "posterior_variance": pv}
write_evil(9, d5)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
