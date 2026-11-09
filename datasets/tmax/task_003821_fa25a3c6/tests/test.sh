#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import math
import os
import re
import subprocess
import sys
import time

import pytest

WORKSPACE = '/home/user/workspace/pynode_proc'
METRIC_FILE = os.path.join(WORKSPACE, 'metric.txt')
FLOAT_RE = re.compile(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')


def test_metric_threshold():
    assert os.path.isfile(METRIC_FILE), (
        f"Metric file {METRIC_FILE} does not exist. Did you run the benchmark and save the output?"
    )
    with open(METRIC_FILE, 'r') as f:
        content = f.read().strip()
    assert FLOAT_RE.fullmatch(content), f"Could not parse {METRIC_FILE} as one floating-point number: {content!r}"
    val = float(content)
    assert math.isfinite(val) and val >= 0, f"Invalid execution time: {val}"
    assert val <= 0.5, f"Execution time {val}s exceeds the maximum allowed time of 0.5s."


def test_c_extension_built():
    so_files = [f for f in os.listdir(WORKSPACE) if f.endswith('.so')]
    assert len(so_files) > 0, (
        "No compiled C extension (.so) found in the workspace directory. "
        "Did you fix setup.py and run 'pip install -e .'?"
    )


def test_setup_builds_extension():
    result = subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '-e', '.'],
        cwd=WORKSPACE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120,
    )
    assert result.returncode == 0, f"pip install -e . failed:\n{result.stdout}"
    assert glob.glob(os.path.join(WORKSPACE, '_fastnode*.so')), "setup.py did not build _fastnode in place"


def test_required_property_suite_passes():
    result = subprocess.run(
        [sys.executable, '-m', 'pytest', 'test_prop.py', '-q'],
        cwd=WORKSPACE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120,
    )
    assert result.returncode == 0, f"test_prop.py failed or crashed:\n{result.stdout}"


def _load_library():
    candidates = glob.glob(os.path.join(WORKSPACE, '_fastnode*.so'))
    assert candidates, "No _fastnode shared library was produced"
    lib = ctypes.CDLL(candidates[0])
    try:
        process = lib.process_node
    except AttributeError as exc:
        pytest.fail(f"The extension does not export process_node: {exc}")
    return lib, process


class DataNode(ctypes.Structure):
    _fields_ = [
        ('id', ctypes.c_int),
        ('value', ctypes.c_float),
        ('buffer', ctypes.c_char * 256),
    ]


class GuardedNode(ctypes.Structure):
    _fields_ = [
        ('before', ctypes.c_ubyte * 32),
        ('node', DataNode),
        ('after', ctypes.c_ubyte * 32),
    ]


def test_exported_api_layout_and_memory_safety():
    assert ctypes.sizeof(DataNode) == 264
    assert DataNode.id.offset == 0
    assert DataNode.value.offset == 4
    assert DataNode.buffer.offset == 8

    _, process = _load_library()
    process.argtypes = [ctypes.POINTER(DataNode)]
    process.restype = None

    guarded = GuardedNode()
    guarded.before[:] = bytes([0xA5]) * 32
    guarded.after[:] = bytes([0x5A]) * 32
    guarded.node.id = 1234567
    guarded.node.value = 1.25

    process(ctypes.byref(guarded.node))

    assert guarded.node.id == 1234567, "process_node corrupted the id field"
    assert guarded.node.value == pytest.approx(1.25), "process_node corrupted the value field"
    buffer_address = (
        ctypes.addressof(guarded)
        + GuardedNode.node.offset
        + DataNode.buffer.offset
    )
    assert ctypes.string_at(buffer_address, 256) == b'X' * 256, "process_node did not fill the 256-byte buffer"
    assert bytes(guarded.before) == bytes([0xA5]) * 32, "write occurred before DataNode"
    assert bytes(guarded.after) == bytes([0x5A]) * 32, "out-of-bounds write occurred after DataNode"


def test_independent_performance_target():
    _, process = _load_library()
    process.argtypes = [ctypes.POINTER(DataNode)]
    process.restype = None
    node = DataNode(id=1, value=1.0)

    for _ in range(1000):
        process(ctypes.byref(node))
    start = time.perf_counter()
    for _ in range(1_000_000):
        process(ctypes.byref(node))
    elapsed = time.perf_counter() - start
    assert elapsed < 0.5, f"Independent benchmark took {elapsed}s, exceeding 0.5s"


def test_benchmark_script_executes_and_meets_target():
    result = subprocess.run(
        [sys.executable, 'benchmark.py'], cwd=WORKSPACE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120,
    )
    assert result.returncode == 0, f"benchmark.py failed:\n{result.stdout}\n{result.stderr}"
    output = result.stdout.strip()
    assert FLOAT_RE.fullmatch(output), f"benchmark.py must output one floating-point value, got: {output!r}"
    elapsed = float(output)
    assert math.isfinite(elapsed) and elapsed >= 0, f"benchmark.py returned invalid time {elapsed}"
    assert elapsed < 0.5, f"benchmark.py reported {elapsed}s, exceeding 0.5s"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
