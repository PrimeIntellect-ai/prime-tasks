#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verify_instrument
cat <<'PY_EOF' > /tmp/verify_instrument/sitecustomize.py
import os

_EVENT_FILE = os.environ.get("VERIFY_EVENT_FILE")

def _event(name):
    if not _EVENT_FILE:
        return
    try:
        fd = os.open(_EVENT_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, (name + "\n").encode())
        finally:
            os.close(fd)
    except Exception:
        pass

import queue as _queue

_OriginalQueue = _queue.Queue
class _ObservedQueue(_OriginalQueue):
    def __init__(self, *args, **kwargs):
        _event("queue_init")
        super().__init__(*args, **kwargs)
_queue.Queue = _ObservedQueue

if hasattr(_queue, "SimpleQueue"):
    _OriginalSimpleQueue = _queue.SimpleQueue
    class _ObservedSimpleQueue(_OriginalSimpleQueue):
        def __init__(self, *args, **kwargs):
            _event("queue_init")
            super().__init__(*args, **kwargs)
    _queue.SimpleQueue = _ObservedSimpleQueue

import threading as _threading
_OriginalThreadStart = _threading.Thread.start
def _thread_start(self, *args, **kwargs):
    _event("worker_start")
    return _OriginalThreadStart(self, *args, **kwargs)
_threading.Thread.start = _thread_start

try:
    import multiprocessing as _multiprocessing
    for _name in ("Queue", "JoinableQueue", "SimpleQueue"):
        if hasattr(_multiprocessing, _name):
            _original = getattr(_multiprocessing, _name)
            def _make_wrapper(original):
                def _wrapper(*args, **kwargs):
                    _event("queue_init")
                    return original(*args, **kwargs)
                return _wrapper
            setattr(_multiprocessing, _name, _make_wrapper(_original))

    import multiprocessing.process as _mp_process
    _OriginalProcessStart = _mp_process.BaseProcess.start
    def _process_start(self, *args, **kwargs):
        _event("worker_start")
        return _OriginalProcessStart(self, *args, **kwargs)
    _mp_process.BaseProcess.start = _process_start
except Exception:
    pass
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import shutil
import subprocess
from pathlib import Path

from packaging.version import Version

HOME = Path("/home/user")
LOG_DIR = HOME / "build_logs"
OUTPUT = HOME / "best_version.txt"
EVENTS = Path("/tmp/verifier_events.log")
INSTRUMENT = "/tmp/verify_instrument"

ORIGINAL_LOGS = {
    "1.0.0": [("ALLOC", 400000), ("FREE", 100000), ("ALLOC", 50000)],
    "1.2.0": [("ALLOC", 300000), ("ALLOC", 300000), ("FREE", 100000)],
    "1.10.0": [("ALLOC", 250000), ("ALLOC", 200000), ("FREE", 400000)],
    "2.0.0": [("ALLOC", 550000), ("FREE", 550000)],
    "1.9.5": [("ALLOC", 490000), ("FREE", 100000)],
    "1.9.11": [("ALLOC", 400000)],
}

DYNAMIC_CASES = [
    {
        "9.9.9": [("ALLOC", 500000)],
        "9.10.0": [("ALLOC", 260000), ("FREE", 60000), ("ALLOC", 300000)],
        "10.0.0": [("ALLOC", 500001)],
        "8.40.2": [("ALLOC", 100000), ("ALLOC", 250000), ("FREE", 350000)],
    },
    {
        "3.19.8": [("ALLOC", 480000), ("FREE", 470000), ("ALLOC", 20000)],
        "3.20.0": [("ALLOC", 320000), ("ALLOC", 190000), ("FREE", 10000)],
        "4.0.0": [("ALLOC", 250000), ("FREE", 100000), ("ALLOC", 340000)],
        "4.0.1": [("ALLOC", 300000), ("FREE", 100000), ("ALLOC", 300001)],
        "2.100.7": [("ALLOC", 499999), ("FREE", 499999)],
    },
]

def write_logs(spec):
    if LOG_DIR.exists():
        shutil.rmtree(LOG_DIR)
    LOG_DIR.mkdir(parents=True)
    for version, operations in spec.items():
        text = "".join(f"{operation} {amount}\n" for operation, amount in operations)
        (LOG_DIR / f"v{version}.log").write_text(text)

def expected_for(spec):
    valid = []
    for version, operations in spec.items():
        current = 0
        peak = 0
        for operation, amount in operations:
            current += amount if operation == "ALLOC" else -amount
            peak = max(peak, current)
        if peak <= 500000:
            valid.append(version)
    assert valid
    return max(valid, key=Version)

def python_candidates():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"build_logs", "__pycache__", ".cache", ".local"} and not d.startswith(".")]
        for name in files:
            if name.endswith(".py"):
                candidates.append(Path(root) / name)
    return sorted(candidates)

def has_required_structure(path):
    try:
        tree = ast.parse(path.read_text())
    except Exception:
        return False

    aliases = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                aliases[item.asname or item.name] = item.name
        elif isinstance(node, ast.ImportFrom) and node.module:
            for item in node.names:
                aliases[item.asname or item.name] = node.module + "." + item.name

    def call_name(node):
        if isinstance(node, ast.Name):
            return aliases.get(node.id, node.id)
        if isinstance(node, ast.Attribute):
            base = call_name(node.value)
            return (base + "." if base else "") + node.attr
        return ""

    calls = [call_name(node.func) for node in ast.walk(tree) if isinstance(node, ast.Call)]
    queue_create = any(name.split(".")[-1] in {"Queue", "JoinableQueue", "SimpleQueue"} for name in calls)
    worker_create = any(name.split(".")[-1] in {"Thread", "Process", "Pool", "ThreadPool", "ThreadPoolExecutor", "ProcessPoolExecutor"} for name in calls)
    queue_put = any(name.split(".")[-1] in {"put", "put_nowait"} for name in calls)
    queue_get = any(name.split(".")[-1] in {"get", "get_nowait"} for name in calls)
    return queue_create and worker_create and queue_put and queue_get

def run_script(path, spec, require_concurrency=False):
    write_logs(spec)
    OUTPUT.unlink(missing_ok=True)
    EVENTS.unlink(missing_ok=True)
    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = INSTRUMENT + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["VERIFY_EVENT_FILE"] = str(EVENTS)
    try:
        result = subprocess.run(
            ["python3", str(path)], cwd=str(HOME), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
    except (subprocess.TimeoutExpired, OSError):
        return False
    if result.returncode != 0 or not OUTPUT.is_file():
        return False
    if OUTPUT.read_text().strip() != expected_for(spec):
        return False
    if require_concurrency:
        observed = set(EVENTS.read_text().splitlines()) if EVENTS.exists() else set()
        if "queue_init" not in observed or "worker_start" not in observed:
            return False
    return True

SCRIPT = None
SETUP_ERROR = None
for candidate in python_candidates():
    if has_required_structure(candidate) and run_script(candidate, ORIGINAL_LOGS, require_concurrency=True):
        SCRIPT = candidate
        break
if SCRIPT is None:
    SETUP_ERROR = "No executable Python script using a queue and concurrent workers correctly processed the logs."

def test_python_script_exists_and_runs_with_required_concurrency():
    assert SCRIPT is not None, SETUP_ERROR

def test_best_version_file_exists():
    assert os.path.isfile("/home/user/best_version.txt"), "The file /home/user/best_version.txt was not created."

def test_best_version_content():
    with open("/home/user/best_version.txt", "r") as f:
        content = f.read().strip()
    assert content == "1.10.0", f"Expected '1.10.0' in /home/user/best_version.txt, but got '{content}'"

def test_script_recomputes_peak_memory_and_semantic_maximum():
    assert SCRIPT is not None, SETUP_ERROR
    for spec in DYNAMIC_CASES:
        assert run_script(SCRIPT, spec), "The script did not correctly recompute the result for changed build logs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
