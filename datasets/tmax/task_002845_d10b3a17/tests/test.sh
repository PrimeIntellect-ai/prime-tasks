#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import secrets
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.request

import numpy as np
import pytest
import redis

FILTER = "/home/user/filter.py"
SERVICES = "/home/user/services"
LOG_PATH = "/home/user/registered.log"


def run_filter(path):
    return subprocess.run(
        ["python3", FILTER, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def test_filter_clean_corpus():
    clean_dir = "/home/user/sim_data/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.npy"))
    assert len(clean_files) > 0, f"No clean files found in {clean_dir}."

    failed_files = []
    for f in clean_files:
        if run_filter(f) != 0:
            failed_files.append(os.path.basename(f))

    assert not failed_files, (
        f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected "
        f"(expected exit code 0). Offending files: {failed_files[:10]}"
    )


def test_filter_evil_corpus():
    evil_dir = "/home/user/sim_data/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.npy"))
    assert len(evil_files) > 0, f"No evil files found in {evil_dir}."

    failed_files = []
    for f in evil_files:
        if run_filter(f) != 1:
            failed_files.append(os.path.basename(f))

    assert not failed_files, (
        f"{len(failed_files)} of {len(evil_files)} evil files bypassed "
        f"(expected exit code 1). Offending files: {failed_files[:10]}"
    )


def test_filter_uses_fourier_transform():
    assert os.path.isfile(FILTER), f"Missing detector: {FILTER}"
    with open(FILTER, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=FILTER)

    module_aliases = {"numpy"}
    fft_object_aliases = set()
    transform_aliases = set()
    transforms = {"fft", "rfft", "fft2", "rfft2", "fftn", "rfftn"}

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == "numpy":
                    module_aliases.add(item.asname or "numpy")
                elif item.name == "numpy.fft":
                    fft_object_aliases.add(item.asname or "numpy.fft")
        elif isinstance(node, ast.ImportFrom):
            if node.module == "numpy":
                for item in node.names:
                    if item.name == "fft":
                        fft_object_aliases.add(item.asname or item.name)
            elif node.module == "numpy.fft":
                for item in node.names:
                    if item.name in transforms:
                        transform_aliases.add(item.asname or item.name)

    def dotted_name(node):
        parts = []
        while isinstance(node, ast.Attribute):
            parts.append(node.attr)
            node = node.value
        if isinstance(node, ast.Name):
            parts.append(node.id)
            return list(reversed(parts))
        return []

    found = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in transform_aliases:
            found = True
            break
        parts = dotted_name(node.func)
        if not parts or parts[-1] not in transforms:
            continue
        if len(parts) >= 3 and parts[0] in module_aliases and parts[1] == "fft":
            found = True
            break
        if len(parts) >= 2 and parts[0] in fft_object_aliases:
            found = True
            break

    assert found, "filter.py does not call a NumPy Fourier transform"


def test_filter_on_unlabeled_generated_inputs():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    root = tempfile.mkdtemp(prefix=secrets.token_hex(8), dir="/tmp")
    cases = []

    try:
        for _ in range(5):
            path = os.path.join(root, secrets.token_hex(12) + ".npy")
            np.save(path, rng.normal(0, 1, (1000, 64)))
            cases.append((path, 0))

        for _ in range(4):
            data = rng.normal(0, 1, (1000, 64))
            t = np.arange(1000)
            frequency_bin = int(rng.integers(70, 310))
            phase = float(rng.uniform(0, 2 * np.pi))
            data += 0.5 * np.sin(2 * np.pi * frequency_bin * t / 1000 + phase)[:, None]
            path = os.path.join(root, secrets.token_hex(12) + ".npy")
            np.save(path, data)
            cases.append((path, 1))

        for bad_value in (np.nan, np.inf, -np.inf):
            data = rng.normal(0, 1, (1000, 64))
            data[int(rng.integers(0, 1000)), int(rng.integers(0, 64))] = bad_value
            path = os.path.join(root, secrets.token_hex(12) + ".npy")
            np.save(path, data)
            cases.append((path, 1))

        rng.shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = run_filter(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Detector failed generated unlabeled cases: {failures}"
    finally:
        shutil.rmtree(root, ignore_errors=True)


def read_log():
    if not os.path.exists(LOG_PATH):
        return []
    entries = []
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            entries.append(json.loads(line))
    return entries


def wait_until(predicate, timeout=35):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    if last_error:
        raise AssertionError(f"Timed out waiting for pipeline: {last_error}")
    raise AssertionError("Timed out waiting for pipeline")


def test_pipeline_registration_log():
    assert os.path.isfile("/home/user/start_all.sh"), "Missing /home/user/start_all.sh"
    assert os.path.isfile(os.path.join(SERVICES, "consumer.sh")), "Missing consumer.sh"

    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    for pattern in ("producer.py", "aggregator.py", "consumer.sh"):
        subprocess.run(["pkill", "-f", pattern], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
    time.sleep(1)

    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    data_dir = os.path.join(SERVICES, "data")
    os.makedirs(data_dir, exist_ok=True)
    for path in glob.glob(os.path.join(data_dir, "*.npy")):
        os.remove(path)

    launch_log = open("/tmp/start_all.verifier.log", "wb")
    subprocess.Popen(
        ["bash", "/home/user/start_all.sh"],
        stdout=launch_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    r = redis.Redis(host="localhost", port=6379, db=0)
    wait_until(lambda: r.ping() is True)

    def http_ready(url):
        try:
            urllib.request.urlopen(url, timeout=1)
            return True
        except urllib.error.HTTPError:
            return True
        except Exception:
            return False

    wait_until(lambda: http_ready("http://localhost:8080/"))
    wait_until(lambda: http_ready("http://localhost:9090/register"))
    wait_until(lambda: os.path.exists(LOG_PATH) and len(read_log()) == 10 and r.llen("raw_data_queue") == 0)
    time.sleep(2)

    # Preserve the original registration assertions, but only after launching
    # the pipeline from a clean log and queue.
    assert os.path.exists(LOG_PATH), (
        f"Log file {LOG_PATH} does not exist. The pipeline likely failed to run or register files."
    )
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    lines = [line for line in content.split("\n") if line.strip()]
    assert len(lines) == 10, f"Expected exactly 10 registered files in {LOG_PATH}, found {len(lines)}."

    initial_ids = []
    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse line as JSON in {LOG_PATH}: {line}")
        file_id = data.get("file_id", "")
        status = data.get("status", "")
        assert "evil" not in file_id.lower(), f"An evil file ID ('{file_id}') was improperly registered in the log!"
        assert "clean" in file_id.lower(), f"Unrecognized file ID format ('{file_id}') registered."
        assert status == "clean", f"Expected status 'clean' in payload, got '{status}'."
        initial_ids.append(file_id)

    assert set(initial_ids) == {f"clean_{i}" for i in range(10)}, "Registered IDs do not match producer output"
    assert len(initial_ids) == len(set(initial_ids)), "Producer output was registered more than once"

    # Exercise the running producer HTTP server, Redis queue, consumer, detector,
    # and aggregator with unpredictable IDs that carry no class label.
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    generated = []
    expected_registered = set()

    for _ in range(2):
        file_id = secrets.token_hex(12)
        np.save(os.path.join(data_dir, file_id + ".npy"), rng.normal(0, 1, (1000, 64)))
        generated.append(file_id)
        expected_registered.add(file_id)

    for _ in range(2):
        file_id = secrets.token_hex(12)
        data = rng.normal(0, 1, (1000, 64))
        t = np.arange(1000)
        frequency_bin = int(rng.integers(80, 300))
        data += 0.5 * np.sin(2 * np.pi * frequency_bin * t / 1000 + rng.uniform(0, 2 * np.pi))[:, None]
        np.save(os.path.join(data_dir, file_id + ".npy"), data)
        generated.append(file_id)

    for _ in range(2):
        file_id = secrets.token_hex(12)
        data = rng.normal(0, 1, (1000, 64))
        data[int(rng.integers(0, 1000)), int(rng.integers(0, 64))] = np.nan
        np.save(os.path.join(data_dir, file_id + ".npy"), data)
        generated.append(file_id)

    rng.shuffle(generated)
    for file_id in generated:
        with urllib.request.urlopen(f"http://localhost:8080/data/{file_id}.npy", timeout=3) as response:
            assert response.status == 200 and len(response.read()) > 0
        r.rpush("raw_data_queue", file_id)

    wait_until(lambda: r.llen("raw_data_queue") == 0)
    wait_until(lambda: expected_registered.issubset({x.get("file_id") for x in read_log()}))
    time.sleep(3)

    final_entries = read_log()
    custom_entries = [x for x in final_entries if x.get("file_id") in set(generated)]
    assert {x.get("file_id") for x in custom_entries} == expected_registered, (
        "The running consumer did not register exactly the generated clean inputs"
    )
    assert len(custom_entries) == len(expected_registered), "Generated inputs were registered more than once"
    assert all(x.get("status") == "clean" for x in custom_entries), "Incorrect registration status"
    assert len(final_entries) == 10 + len(expected_registered), "Contaminated generated inputs were registered"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
