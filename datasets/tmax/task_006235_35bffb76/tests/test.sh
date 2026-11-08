#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import subprocess
import time

import h5py
import numpy as np
import pytest

RESULTS = "/home/user/results.json"
H5_PATH = "/home/user/data/seqs.h5"
EXPECTED_KEYS = {"matched_count", "total_gc", "total_bases", "average_gc_ratio"}


def load_results():
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not a valid JSON.")


def test_results_file_exists():
    """Check if the results JSON file exists."""
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist."


def test_results_content():
    """Check the submitted result for the original deterministic data."""
    results = load_results()

    missing_keys = EXPECTED_KEYS - results.keys()
    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"
    assert set(results.keys()) == EXPECTED_KEYS, \
        f"results.json must contain exactly {sorted(EXPECTED_KEYS)}"

    expected_matched_count = 1494
    expected_total_bases = 222956
    expected_total_gc = 111306
    expected_average_gc_ratio = 0.499229

    assert isinstance(results["matched_count"], int), "matched_count must be an integer"
    assert results["matched_count"] == expected_matched_count, \
        f"Expected matched_count to be {expected_matched_count}, got {results['matched_count']}"

    assert isinstance(results["total_bases"], int), "total_bases must be an integer"
    assert results["total_bases"] == expected_total_bases, \
        f"Expected total_bases to be {expected_total_bases}, got {results['total_bases']}"

    assert isinstance(results["total_gc"], int), "total_gc must be an integer"
    assert results["total_gc"] == expected_total_gc, \
        f"Expected total_gc to be {expected_total_gc}, got {results['total_gc']}"

    assert isinstance(results["average_gc_ratio"], float), "average_gc_ratio must be a float"
    assert math.isclose(results["average_gc_ratio"], expected_average_gc_ratio, rel_tol=1e-5), \
        f"Expected average_gc_ratio to be {expected_average_gc_ratio}, got {results['average_gc_ratio']}"


def candidate_scripts():
    parallel_markers = (
        "multiprocessing", "processpoolexecutor", "threadpoolexecutor",
        "concurrent.futures", "threading", "pool(", "os.fork", "joblib",
        "dask", "ray", "mpi", "xargs", "gnu parallel",
    )
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"data", ".cache", "__pycache__"}]
        for name in files:
            path = os.path.join(root, name)
            if path == RESULTS or os.path.getsize(path) > 2_000_000:
                continue
            try:
                with open(path, "rb") as f:
                    raw = f.read()
                text = raw.decode("utf-8").lower()
            except (OSError, UnicodeDecodeError):
                continue
            if "seqs.h5" not in text or "results.json" not in text:
                continue
            if not any(marker in text for marker in parallel_markers):
                continue
            candidates.append(path)
    return sorted(candidates, key=lambda p: os.path.getmtime(p), reverse=True)


def command_for(path):
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith((".sh", ".bash")):
        return ["bash", path]
    with open(path, "rb") as f:
        first = f.readline(256)
    if b"python" in first:
        return ["python3", path]
    if b"sh" in first:
        return ["bash", path]
    if os.access(path, os.X_OK):
        return [path]
    return None


def execution_entity_count(root_pid):
    info = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            ppid = None
            threads = 1
            with open(f"/proc/{entry}/status", "r") as f:
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                    elif line.startswith("Threads:"):
                        threads = int(line.split()[1])
            info[int(entry)] = (ppid, threads)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    family = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _) in info.items():
            if ppid in family and pid not in family:
                family.add(pid)
                changed = True
    return sum(info.get(pid, (None, 0))[1] for pid in family)


def run_and_observe(path):
    command = command_for(path)
    if command is None:
        return False
    env = os.environ.copy()
    env.update({
        "OPENBLAS_NUM_THREADS": "1",
        "OMP_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
        "NUMEXPR_NUM_THREADS": "1",
    })
    proc = subprocess.Popen(
        command,
        cwd=os.path.dirname(path) or "/home/user",
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    observed_parallel = False
    deadline = time.time() + 90
    while proc.poll() is None and time.time() < deadline:
        try:
            # At least three simultaneous execution entities means the main
            # program plus two worker processes/threads (or a shell plus two workers).
            if execution_entity_count(proc.pid) >= 3:
                observed_parallel = True
        except (FileNotFoundError, ProcessLookupError):
            pass
        time.sleep(0.001)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        return False
    return proc.returncode == 0 and observed_parallel


def make_probe_h5():
    rng = random.SystemRandom()
    primer = b"ATGCGATC"
    sequences = []
    for i in range(10000):
        length = rng.randint(1200, 2200)
        table = bytes(ord("ACGT")[j & 3] for j in range(256))
        seq = os.urandom(length).translate(table)
        if rng.random() < 0.19:
            pos = rng.randrange(0, length - len(primer) + 1)
            seq = seq[:pos] + primer + seq[pos + len(primer):]
        sequences.append(seq)

    matched = [s for s in sequences if primer in s]
    expected = {
        "matched_count": len(matched),
        "total_gc": sum(s.count(b"G") + s.count(b"C") for s in matched),
        "total_bases": sum(len(s) for s in matched),
    }
    expected["average_gc_ratio"] = round(
        expected["total_gc"] / expected["total_bases"], 6
    )

    width = max(map(len, sequences))
    with h5py.File(H5_PATH, "w") as f:
        f.create_dataset("sequences", data=np.asarray(sequences, dtype=f"S{width}"))
    return expected


def dynamic_result_is_correct(expected):
    if not os.path.isfile(RESULTS):
        return False
    try:
        results = load_results()
    except Exception:
        return False
    return (
        set(results.keys()) == EXPECTED_KEYS
        and type(results["matched_count"]) is int
        and type(results["total_gc"]) is int
        and type(results["total_bases"]) is int
        and type(results["average_gc_ratio"]) is float
        and results["matched_count"] == expected["matched_count"]
        and results["total_gc"] == expected["total_gc"]
        and results["total_bases"] == expected["total_bases"]
        and results["average_gc_ratio"] == expected["average_gc_ratio"]
    )


def test_z_script_reads_hdf5_and_computes_in_parallel():
    scripts = candidate_scripts()
    assert scripts, "No submitted script that reads seqs.h5 and implements parallel processing was found"

    backup = "/tmp/original_seqs.h5"
    shutil.copy2(H5_PATH, backup)
    try:
        expected = make_probe_h5()
        failures = []
        for script in scripts:
            try:
                if os.path.exists(RESULTS):
                    os.remove(RESULTS)
                parallel = run_and_observe(script)
                if parallel and dynamic_result_is_correct(expected):
                    return
                failures.append(f"{script}: parallel={parallel}, correct={dynamic_result_is_correct(expected)}")
            except Exception as exc:
                failures.append(f"{script}: {exc}")
        pytest.fail("No submitted script produced the derived result while using multiple workers. " + "; ".join(failures))
    finally:
        shutil.copy2(backup, H5_PATH)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
