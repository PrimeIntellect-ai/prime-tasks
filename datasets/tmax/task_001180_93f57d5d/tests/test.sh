#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import signal
import struct
import subprocess
import time
import uuid

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
import redis

APP_DIR = "/home/user/simulation_app"
WORKER_LOG = os.path.join(APP_DIR, "worker.log")
QUEUE = "job_queue"


def matching_pids(fragment):
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            if fragment in cmdline:
                result.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def signal_pids(pids, sig):
    for pid in pids:
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass


def terminate_matching(fragment):
    pids = matching_pids(fragment)
    signal_pids(pids, signal.SIGTERM)
    time.sleep(0.5)
    signal_pids(matching_pids(fragment), signal.SIGKILL)


def wait_until(predicate, timeout=10, interval=0.1):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"Condition was not met: {last_error}")
    raise AssertionError("Condition was not met before timeout")


def log_contains(token):
    if not os.path.exists(WORKER_LOG):
        return False
    with open(WORKER_LOG, "r", errors="replace") as f:
        return token in f.read()


def test_service_composition():
    start_script = os.path.join(APP_DIR, "start_services.sh")
    worker_script = os.path.join(APP_DIR, "worker.py")
    assert os.path.isfile(start_script), f"Startup script {start_script} not found."
    assert os.path.isfile(worker_script), f"Worker script {worker_script} not found."

    # Ensure the test exercises the submitted service composition rather than a
    # stale process left running before verification.
    terminate_matching("/home/user/simulation_app/api.py")
    terminate_matching("/home/user/simulation_app/worker.py")
    subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    signal_pids(matching_pids("redis-server"), signal.SIGTERM)
    if os.path.exists(WORKER_LOG):
        os.remove(WORKER_LOG)

    try:
        subprocess.run(["bash", start_script], cwd=APP_DIR, check=True,
                       timeout=10, start_new_session=True)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Failed to run start_services.sh: {exc}")

    r = redis.Redis(host="localhost", port=6379, db=0,
                    socket_connect_timeout=1, socket_timeout=1)
    wait_until(lambda: r.ping() is True, timeout=10)
    assert r.ping() is True, "Redis did not respond on localhost:6379."

    # A real worker launched by the composition must be present. Stop it so the
    # API-to-Redis leg can be observed independently of worker processing.
    wait_until(lambda: len(matching_pids("/home/user/simulation_app/worker.py")) > 0,
               timeout=8)
    worker_pids = matching_pids("/home/user/simulation_app/worker.py")
    assert worker_pids, "start_services.sh did not launch worker.py."
    signal_pids(worker_pids, signal.SIGSTOP)
    time.sleep(0.3)

    r.delete(QUEUE)
    api_token = "verification_job_" + uuid.uuid4().hex
    payload = json.dumps({"job": api_token})
    try:
        response = subprocess.run(
            ["curl", "--fail", "--silent", "--show-error", "--max-time", "5",
             "-X", "POST", "http://localhost:5050/submit",
             "-d", payload, "-H", "Content-Type: application/json"],
            check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        signal_pids(worker_pids, signal.SIGCONT)
        pytest.fail(f"Failed to submit job to API: {exc.stderr}")

    wait_until(lambda: r.llen(QUEUE) == 1, timeout=5)
    queued = r.lindex(QUEUE, 0)
    assert queued is not None, "The API did not place the submitted job in Redis."
    assert json.loads(queued.decode())["job"] == api_token, \
        "The API did not enqueue the submitted JSON job in Redis."

    # A fake API that writes worker.log itself must not satisfy the test.
    time.sleep(0.5)
    assert not log_contains(api_token), \
        "The API wrote the worker success record while the worker was stopped."

    signal_pids(worker_pids, signal.SIGCONT)
    wait_until(lambda: log_contains(api_token), timeout=10)
    assert os.path.exists(WORKER_LOG), f"Worker log {WORKER_LOG} was not created."
    assert f"Processed {api_token}" in open(WORKER_LOG, errors="replace").read(), \
        "Worker did not process the API-submitted job successfully."

    # Independently execute the demanded worker under MPI and inject a job
    # directly into Redis. This proves worker.py, rather than an API shortcut,
    # consumes the queue and writes the success log.
    terminate_matching("/home/user/simulation_app/worker.py")
    r.delete(QUEUE)
    mpi_token = "mpi_direct_" + uuid.uuid4().hex
    env = os.environ.copy()
    env["REDIS_URL"] = "redis://localhost:6379/0"
    env["OMPI_ALLOW_RUN_AS_ROOT"] = "1"
    env["OMPI_ALLOW_RUN_AS_ROOT_CONFIRM"] = "1"
    mpi_worker = subprocess.Popen(
        ["mpirun", "--allow-run-as-root", "-np", "1", "python3", worker_script],
        cwd=APP_DIR, env=env, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        time.sleep(1.5)
        assert mpi_worker.poll() is None, "worker.py exited when launched under MPI."
        r.lpush(QUEUE, json.dumps({"job": mpi_token}))
        wait_until(lambda: log_contains(mpi_token), timeout=10)
        assert f"Processed {mpi_token}" in open(WORKER_LOG, errors="replace").read(), \
            "MPI worker did not process a job injected directly into Redis."
    finally:
        try:
            os.killpg(mpi_worker.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            mpi_worker.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(mpi_worker.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def run_classifier(classifier_script, csv_path, expected):
    plot_file = "/home/user/latest_plot.png"
    if os.path.exists(plot_file):
        os.remove(plot_file)

    result = subprocess.run(
        ["python3", classifier_script, csv_path],
        capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, \
        f"Classifier failed for {csv_path}: {result.stderr}"
    assert result.stdout.strip() == expected, \
        f"Expected {expected} for {csv_path}, got {result.stdout!r}"
    assert os.path.exists(plot_file), \
        f"Plot file {plot_file} was not generated for {csv_path}."
    assert os.path.getsize(plot_file) > 1000, "Generated plot is only a placeholder."

    with open(plot_file, "rb") as f:
        header = f.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "latest_plot.png is not a PNG file."
    width, height = struct.unpack(">II", header[16:24])
    assert width >= 100 and height >= 100, "Generated plot is not a usable plot image."
    image = mpimg.imread(plot_file).copy()
    assert float(np.std(image)) > 0.001, "Generated plot has no visible plotted content."
    return image


def test_adversarial_corpus_classifier():
    classifier_script = "/home/user/trace_classifier.py"
    assert os.path.isfile(classifier_script), \
        f"Classifier script {classifier_script} not found."

    with open(classifier_script, "r", errors="replace") as f:
        source = f.read().lower()
    assert "dt" in source, "Classifier does not reference the dt column."
    assert any(term in source for term in ("hist", "kde", "gaussian_kde", "density")), \
        "Classifier does not appear to perform histogram or KDE density estimation."

    clean_corpus = glob.glob("/home/user/corpus/clean/*.csv")
    evil_corpus = glob.glob("/home/user/corpus/evil/*.csv")
    assert len(clean_corpus) > 0, "No clean corpus files found."
    assert len(evil_corpus) > 0, "No evil corpus files found."

    clean_failures = []
    for path in clean_corpus:
        try:
            run_classifier(classifier_script, path, "CLEAN")
        except AssertionError:
            clean_failures.append(os.path.basename(path))

    evil_failures = []
    for path in evil_corpus:
        try:
            run_classifier(classifier_script, path, "EVIL")
        except AssertionError:
            evil_failures.append(os.path.basename(path))

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_corpus)} clean modified/rejected: "
                      + ", ".join(clean_failures))
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_corpus)} evil bypassed: "
                      + ", ".join(evil_failures))
    if errors:
        pytest.fail(" | ".join(errors))

    # Hidden traces are repeatedly written to the same neutral path in random
    # order. Labels are derived from newly generated dt values, so directory,
    # filename, and invocation order cannot reveal the answer.
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    neutral_dir = "/tmp/trace_inputs_" + uuid.uuid4().hex
    os.makedirs(neutral_dir)
    neutral_path = os.path.join(neutral_dir, "trace.csv")

    cases = []
    for pair in range(4):
        step = np.arange(100)
        trace_time = step * rng.uniform(0.005, 0.02)
        error = rng.uniform(0.0, 0.1, 100)
        center = rng.uniform(0.008, 0.014)
        base_dt = np.clip(rng.normal(center, rng.uniform(0.001, 0.0018), 100),
                          2e-3, None)
        cases.append(("CLEAN", step, trace_time, base_dt.copy(), error))

        collapsed_dt = base_dt.copy()
        start = int(rng.integers(70, 84))
        collapsed_dt[start:start + 15] = rng.normal(1e-7, 1e-8, 15)
        cases.append(("EVIL", step, trace_time, collapsed_dt, error))

    random.SystemRandom().shuffle(cases)
    representative = {}
    for expected, step, trace_time, dt, error in cases:
        pd.DataFrame({"step": step, "time": trace_time, "dt": dt,
                      "error": error}).to_csv(neutral_path, index=False)
        representative[expected] = run_classifier(classifier_script, neutral_path, expected)

    assert set(representative) == {"CLEAN", "EVIL"}
    clean_image = representative["CLEAN"]
    evil_image = representative["EVIL"]
    assert clean_image.shape != evil_image.shape or not np.array_equal(clean_image, evil_image), \
        "The saved plot did not change when the dt density changed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
