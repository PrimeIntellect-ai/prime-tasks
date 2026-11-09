#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev gcc imagemagick fonts-dejavu-core
pip3 install pytest hypothesis

mkdir -p /app
# Generate the struct_spec.png image
convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'REQUIRED STRUCT LAYOUT:\ntypedef struct {\n    int id;\n    float value;\n    char buffer[256];\n} DataNode;\nEXPORTED API: void process_node(DataNode* node);'" /app/struct_spec.png

mkdir -p /home/user/workspace/pynode_proc

cat << 'EOF' > /home/user/workspace/pynode_proc/setup.py
from setuptools import setup
# Missing Extension import and incorrectly references .cpp
setup(
    name='pynode_proc',
    ext_modules=[Extension('_fastnode', ['fastnode.cpp'])]
)
EOF

cat << 'EOF' > /home/user/workspace/pynode_proc/fastnode.c
typedef struct {
    int id;
    float value;
    char buffer[256];
} DataNode;

void process_node(DataNode* node) {
    for (int i = 0; i <= 256; i++) { // Off-by-one buffer overflow
        node->buffer[i] = 'X';
    }
}
EOF

cat << 'EOF' > /home/user/workspace/pynode_proc/test_prop.py
import ctypes
import os
import glob
from hypothesis import given, strategies as st

class DataNode(ctypes.Structure):
    _fields_ = [
        ("id", ctypes.c_int),
        ("value", ctypes.c_float),
        ("buffer", ctypes.c_char * 256)
    ]

def get_lib():
    so_files = glob.glob(os.path.join(os.path.dirname(__file__), "build", "lib*", "_fastnode*.so"))
    if not so_files:
        so_files = glob.glob(os.path.join(os.path.dirname(__file__), "_fastnode*.so"))
    if so_files:
        lib = ctypes.CDLL(so_files[0])
        lib.process_node.argtypes = [ctypes.POINTER(DataNode)]
        lib.process_node.restype = None
        return lib
    return None

@given(st.integers(), st.floats(allow_nan=False, allow_infinity=False))
def test_process_node(id_val, float_val):
    lib = get_lib()
    if lib is None:
        return
    node = DataNode(id=id_val, value=float_val)
    lib.process_node(ctypes.byref(node))
    assert node.buffer[0] == b'X'
EOF

cat << 'EOF' > /home/user/workspace/pynode_proc/benchmark.py
import ctypes
import os
import glob
import time

class DataNode(ctypes.Structure):
    _fields_ = [
        ("id", ctypes.c_int),
        ("value", ctypes.c_float),
        ("buffer", ctypes.c_char * 256)
    ]

def get_lib():
    so_files = glob.glob(os.path.join(os.path.dirname(__file__), "build", "lib*", "_fastnode*.so"))
    if not so_files:
        so_files = glob.glob(os.path.join(os.path.dirname(__file__), "_fastnode*.so"))
    if so_files:
        lib = ctypes.CDLL(so_files[0])
        lib.process_node.argtypes = [ctypes.POINTER(DataNode)]
        lib.process_node.restype = None
        return lib
    return None

def run_benchmark():
    lib = get_lib()
    if lib is None:
        print("Library not found, using slow fallback...")
        time.sleep(2.5)
        print(2.5)
        return 2.5

    node = DataNode(id=1, value=1.0)
    start = time.time()
    for _ in range(1000000):
        lib.process_node(ctypes.byref(node))
    end = time.time()
    elapsed = end - start
    print(elapsed)
    return elapsed

if __name__ == "__main__":
    run_benchmark()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
