#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import importlib.util
import json
import os
import signal
import subprocess
import sys
import time

import pytest
import redis
import requests
import matplotlib.image as mpimg

APP_DIR = "/home/user/app"
CLEAN_DIR = os.path.join(APP_DIR, "data/clean")
EVIL_DIR = os.path.join(APP_DIR, "data/evil")


def load_submission_detector():
    path = os.path.join(APP_DIR, "detector.py")
    spec = importlib.util.spec_from_file_location("audited_submission_detector", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def corpus_rows(directory):
    rows = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".csv"):
            with open(os.path.join(directory, name), newline="") as f:
                rows.extend(list(csv.DictReader(f)))
    return rows


def stop_services():
    subprocess.run(["pkill", "-f", "uvicorn api:app"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "python3 worker.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.5)


def test_env_file_correct():
    env_path = os.path.join(APP_DIR, ".env")
    assert os.path.isfile(env_path), f".env file missing at {env_path}"
    with open(env_path, "r") as f:
        content = f.read()
    assert "REDIS_URL" in content and "6379" in content, "REDIS_URL not correctly set in .env"
    assert "API_PORT=8000" in content.replace(" ", ""), "API_PORT not correctly set in .env"

    values = {}
    for line in content.splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("'\"")
    redis_url = values.get("REDIS_URL", "")
    assert redis_url.startswith(("redis://localhost:6379", "redis://127.0.0.1:6379")), \
        f"REDIS_URL must point to the local Redis service, got {redis_url!r}"
    assert values.get("API_PORT") == "8000"


def test_plot_results_fixed():
    plot_path = os.path.join(APP_DIR, "plot_results.py")
    assert os.path.isfile(plot_path), f"plot_results.py missing at {plot_path}"
    with open(plot_path, "r") as f:
        content = f.read()
    assert "Agg" in content or "agg" in content.lower(), \
        "matplotlib backend 'Agg' not found in plot_results.py"

    output = os.path.join(APP_DIR, "summary.png")
    if os.path.exists(output):
        os.unlink(output)
    completed = subprocess.run([sys.executable, plot_path], cwd=APP_DIR,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, timeout=30)
    assert completed.returncode == 0, completed.stdout
    assert os.path.isfile(output) and os.path.getsize(output) > 500, \
        "plot_results.py did not create a substantive summary.png"
    image = mpimg.imread(output)
    assert image.size > 0 and float(image.max() - image.min()) > 0.02, \
        "summary.png is blank or visually uniform"


def test_adversarial_corpus():
    detector = load_submission_detector()
    classify = detector.classify

    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No evil CSV files found."
    assert len(clean_files) > 0, "No clean CSV files found."

    evil_bypassed = []
    clean_modified = []
    for e_file in evil_files:
        with open(os.path.join(EVIL_DIR, e_file), 'r') as f:
            for row in csv.DictReader(f):
                try:
                    if classify(row) is not False:
                        evil_bypassed.append(e_file)
                        break
                except Exception:
                    evil_bypassed.append(e_file)
                    break
    for c_file in clean_files:
        with open(os.path.join(CLEAN_DIR, c_file), 'r') as f:
            for row in csv.DictReader(f):
                try:
                    if classify(row) is not True:
                        clean_modified.append(c_file)
                        break
                except Exception:
                    clean_modified.append(c_file)
                    break

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified[:5])}")
    if errors:
        pytest.fail(" | ".join(errors))

    detector_path = os.path.join(APP_DIR, "detector.py")
    source = open(detector_path).read()
    tree = ast.parse(source)
    imported = {alias.name.split('.')[0] for node in ast.walk(tree)
                if isinstance(node, ast.Import) for alias in node.names}
    imported.update(node.module.split('.')[0] for node in ast.walk(tree)
                    if isinstance(node, ast.ImportFrom) and node.module)
    assert imported.intersection({"numpy", "scipy"}), \
        "detector.py must implement its Bayesian calculation using numpy or scipy"
    assert "amount" in source and "location_frequency" in source, \
        "the detector must use both required observations"

    # Derived probes include low-amount fraud, preventing an amount/ID lookup from
    # satisfying the required two-feature anomaly model.
    probes = []
    for i in range(8):
        probes.append(({"id": f"hidden-clean-{i}",
                        "amount": str(8.75 + 1.25 * i),
                        "location_frequency": str(4 + (i % 3))}, True))
        probes.append(({"id": f"hidden-rare-{i}",
                        "amount": str(9.25 + 1.1 * i),
                        "location_frequency": str((i % 2) * 0.2)}, False))
        probes.append(({"id": f"hidden-large-{i}",
                        "amount": str(4200 + 725 * i),
                        "location_frequency": str(4 + (i % 2))}, False))
    for row, expected in probes:
        result = classify(row)
        assert result is expected, f"classify({row!r}) returned {result!r}, expected {expected!r}"


def test_services_verify_and_end_to_end_processing():
    detector_path = os.path.join(APP_DIR, "detector.py")
    saved_path = "/tmp/submission_detector_for_service.py"
    trace_path = "/tmp/classifier_trace.jsonl"
    start_process = None
    monitor = None

    stop_services()
    if os.path.exists(saved_path):
        os.unlink(saved_path)
    os.rename(detector_path, saved_path)
    wrapper = f'''import importlib.util\nimport json\n_spec = importlib.util.spec_from_file_location("service_submission_detector", {saved_path!r})\n_mod = importlib.util.module_from_spec(_spec)\n_spec.loader.exec_module(_mod)\ndef classify(csv_row_dict):\n    result = _mod.classify(csv_row_dict)\n    with open({trace_path!r}, "a") as _f:\n        _f.write(json.dumps({{"row": dict(csv_row_dict), "result": bool(result), "strict": result is True or result is False}}) + "\\n")\n    return result\n'''
    with open(detector_path, "w") as f:
        f.write(wrapper)
    open(trace_path, "w").close()

    try:
        start_process = subprocess.Popen([os.path.join(APP_DIR, "start_services.sh")],
                                         cwd=APP_DIR, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL,
                                         start_new_session=True)
        deadline = time.time() + 20
        last_error = None
        while time.time() < deadline:
            try:
                assert redis.Redis(host="127.0.0.1", port=6379).ping()
                response = requests.get("http://127.0.0.1:8000/docs", timeout=1)
                if response.status_code == 200:
                    break
            except Exception as exc:
                last_error = exc
            time.sleep(0.25)
        else:
            pytest.fail(f"Redis and FastAPI did not become ready: {last_error}")

        marker = "pipeline-audit-9f31"
        monitor = subprocess.Popen(["stdbuf", "-oL", "redis-cli", "MONITOR"],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True)
        time.sleep(0.4)
        service_rows = [
            ({"id": marker + "-clean", "amount": "13.0", "location_frequency": "5"}, True),
            ({"id": marker + "-rare", "amount": "13.0", "location_frequency": "0"}, False),
            ({"id": marker + "-large", "amount": "7000.0", "location_frequency": "5"}, False),
        ]
        for row, _ in service_rows:
            response = requests.post("http://127.0.0.1:8000/ingest", json=row, timeout=5)
            assert 200 <= response.status_code < 300, \
                f"/ingest rejected a transaction: {response.status_code} {response.text}"

        deadline = time.time() + 12
        observed = []
        while time.time() < deadline:
            observed = []
            if os.path.exists(trace_path):
                for line in open(trace_path):
                    try:
                        observed.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
            ids = {str(item["row"].get("id")) for item in observed}
            if all(row["id"] in ids for row, _ in service_rows):
                break
            time.sleep(0.25)
        else:
            pytest.fail("transactions submitted to FastAPI did not reach detector.py through the worker")

        monitor.terminate()
        monitor_output, _ = monitor.communicate(timeout=5)
        monitor = None
        assert marker in monitor_output, \
            "the ingestion path did not send the submitted transactions through Redis"

        by_id = {str(item["row"].get("id")): item for item in observed}
        for row, expected in service_rows:
            item = by_id[row["id"]]
            assert item["strict"], "service classifier must return an actual bool"
            assert item["result"] is expected, \
                f"worker classified end-to-end row {row!r} incorrectly"

        # verify.py itself must feed every shipped corpus row through the live API/Redis/worker path.
        open(trace_path, "w").close()
        completed = subprocess.run([sys.executable, os.path.join(APP_DIR, "verify.py")],
                                   cwd=APP_DIR, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, timeout=40)
        assert completed.returncode == 0, f"verify.py failed:\n{completed.stdout}"

        expected = {}
        for row in corpus_rows(CLEAN_DIR):
            expected[str(row["id"])] = True
        for row in corpus_rows(EVIL_DIR):
            expected[str(row["id"])] = False

        deadline = time.time() + 12
        verified_rows = []
        while time.time() < deadline:
            verified_rows = []
            for line in open(trace_path):
                try:
                    verified_rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
            seen = {str(item["row"].get("id")) for item in verified_rows}
            if set(expected).issubset(seen):
                break
            time.sleep(0.25)
        else:
            pytest.fail("verify.py did not process every clean and evil corpus row through the worker")

        latest = {str(item["row"].get("id")): item for item in verified_rows}
        for row_id, wanted in expected.items():
            assert latest[row_id]["strict"] and latest[row_id]["result"] is wanted, \
                f"verify.py pipeline produced the wrong result for corpus id {row_id}"
    finally:
        if monitor is not None:
            monitor.terminate()
            try:
                monitor.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                monitor.kill()
        if start_process is not None and start_process.poll() is None:
            try:
                os.killpg(start_process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        stop_services()
        if os.path.exists(detector_path):
            os.unlink(detector_path)
        if os.path.exists(saved_path):
            os.rename(saved_path, detector_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
