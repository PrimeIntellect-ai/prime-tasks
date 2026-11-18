#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc ffmpeg golang
    pip3 install pytest

    mkdir -p /app/legacy_tracker
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user

    # Create Python 2 style C extension
    cat << 'EOF' > /app/legacy_tracker/fastmath.c
#include <Python.h>
#include <math.h>

static PyObject* fastmath_dist(PyObject* self, PyObject* args) {
    double x1, y1, x2, y2;
    if (!PyArg_ParseTuple(args, "dddd", &x1, &y1, &x2, &y2)) return NULL;
    return Py_BuildValue("d", sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2)));
}

static PyMethodDef FastMathMethods[] = {
    {"dist", fastmath_dist, METH_VARARGS, "Calculate Euclidean distance."},
    {NULL, NULL, 0, NULL}
};

PyMODINIT_FUNC initfastmath(void) {
    (void) Py_InitModule("fastmath", FastMathMethods);
}
EOF

    # Create Python 2 style setup.py
    cat << 'EOF' > /app/legacy_tracker/setup.py
from distutils.core import setup, Extension

print "Setting up fastmath..."

module1 = Extension('fastmath', sources = ['fastmath.c'])

setup(name = 'FastMath',
      version = '1.0',
      description = 'Legacy math package',
      ext_modules = [module1])
EOF

    # Create extract.py
    cat << 'EOF' > /app/legacy_tracker/extract.py
import sys
import os
import json
import fastmath

if len(sys.argv) < 2:
    print("Usage: extract.py <frame_dir>")
    sys.exit(1)

frame_dir = sys.argv[1]
frames = [f for f in os.listdir(frame_dir) if os.path.isfile(os.path.join(frame_dir, f))]

# Dummy call to ensure fastmath is used
d = fastmath.dist(0.0, 0.0, 3.0, 4.0)

stats = {
    "frame_count": len(frames),
    "status": "success",
    "test_dist": d
}

with open('/home/user/video_stats.json', 'w') as f:
    json.dump(stats, f)

print("Stats written.")
EOF

    # Generate video with exactly 142 frames (142 frames / 30 fps = 4.733333 seconds)
    ffmpeg -f lavfi -i testsrc=duration=4.733333:rate=30 -c:v libx264 /app/experiment.mp4

    # Generate corpus
    python3 -c '
import json, os

clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

for i in range(20):
    # Clean: max distance is ~14.14
    clean_data = {"id": f"clean_{i}", "points": [{"x": 0.0, "y": 0.0}, {"x": 10.0, "y": 10.0}, {"x": 20.0, "y": 20.0}]}
    with open(os.path.join(clean_dir, f"{i}.json"), "w") as f:
        json.dump(clean_data, f)

    # Evil: distance is ~141.4 (> 50.0)
    evil_data = {"id": f"evil_{i}", "points": [{"x": 0.0, "y": 0.0}, {"x": 100.0, "y": 100.0}, {"x": 20.0, "y": 20.0}]}
    with open(os.path.join(evil_dir, f"{i}.json"), "w") as f:
        json.dump(evil_data, f)
'

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
