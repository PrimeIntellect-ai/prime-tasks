#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import uuid

import numpy as np
import pytest
import redis


def load_filter():
    filter_path = "/home/user/filter_corpus.py"
    assert os.path.isfile(filter_path), f"Filter script {filter_path} is missing."
    spec = importlib.util.spec_from_file_location("filter_corpus", filter_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["filter_corpus"] = module
    spec.loader.exec_module(module)
    assert hasattr(module, "check_matrix"), "Function 'check_matrix' is missing in filter_corpus.py."
    assert callable(module.check_matrix), "check_matrix is not callable."
    return module.check_matrix


def test_redis_port_configured():
    env_path = "/app/services/emitter/.env"
    assert os.path.isfile(env_path), f"Configuration file {env_path} is missing."
    with open(env_path, "r") as f:
        content = f.read()
    assert "REDIS_PORT=6379" in content, "REDIS_PORT was not corrected to 6379 in the .env file."


def test_worker_script_modified():
    worker_path = "/app/services/worker/worker.py"
    assert os.path.isfile(worker_path), f"Worker script {worker_path} is missing."
    with open(worker_path, "r") as f:
        content = f.read()
    assert "filter_corpus" in content, "The worker script does not import 'filter_corpus'."
    assert "check_matrix" in content, "The worker script does not use the 'check_matrix' function."


def test_adversarial_corpus_filter():
    check_matrix = load_filter()
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.csv')]
    assert clean_files, "The clean corpus is empty."
    assert evil_files, "The evil corpus is empty."

    clean_modified = []
    evil_bypassed = []
    for f in clean_files:
        if not check_matrix(os.path.join(clean_dir, f)):
            clean_modified.append(f)
    for f in evil_files:
        if check_matrix(os.path.join(evil_dir, f)):
            evil_bypassed.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    assert not errors, "Adversarial corpus verification failed: " + "; ".join(errors)


def test_generated_hidden_holdout():
    check_matrix = load_filter()
    rng = np.random.default_rng(918273)

    # Clean and evil files deliberately share one randomly named directory and
    # randomly generated filenames, so directory or filename classification fails.
    with tempfile.TemporaryDirectory(prefix="matrix_holdout_") as holdout:
        cases = []
        for _ in range(20):
            mat = rng.uniform(0.1, 1.0, (10, 10))
            cases.append((mat, True))
        for _ in range(20):
            base = rng.random(10)
            mat = np.tile(base, (10, 1)) + rng.normal(0, 1e-8, (10, 10))
            cases.append((mat, False))
        rng.shuffle(cases)

        failures = []
        for mat, expected in cases:
            path = os.path.join(holdout, uuid.uuid4().hex + ".csv")
            np.savetxt(path, mat, delimiter=",")
            actual = check_matrix(path)
            assert isinstance(actual, (bool, np.bool_)), "check_matrix must return a boolean."
            if bool(actual) != expected:
                failures.append((os.path.basename(path), expected, bool(actual)))
        assert not failures, f"Generated holdout misclassifications: {failures}"


def wait_for(predicate, timeout=10.0, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return bool(predicate())


def read_json_lines(path):
    if not os.path.exists(path):
        return []
    records = []
    with open(path, "r") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def test_worker_actually_filters_and_factorizes():
    subprocess.run(["redis-server", "--daemonize", "yes"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    client = redis.Redis(host="localhost", port=6379)
    assert wait_for(lambda: client.ping(), timeout=5), "Redis did not become available."
    client.flushdb()

    log_path = "/app/services/worker/success.log"
    filter_trace = "/tmp/verifier_filter_trace.jsonl"
    nmf_trace = "/tmp/verifier_nmf_trace.jsonl"
    for path in (log_path, filter_trace, nmf_trace):
        if os.path.exists(path):
            os.remove(path)

    instrument_dir = tempfile.mkdtemp(prefix="worker_instrument_")
    sitecustomize = r'''import json
import numpy as np

try:
    import filter_corpus
    _original_check = filter_corpus.check_matrix
    def _tracked_check(path):
        result = _original_check(path)
        with open("/tmp/verifier_filter_trace.jsonl", "a") as f:
            f.write(json.dumps({"path": str(path), "result": bool(result)}) + "\n")
        return result
    filter_corpus.check_matrix = _tracked_check
except Exception:
    pass

try:
    import sklearn.decomposition
    _original_fit_transform = sklearn.decomposition.NMF.fit_transform
    def _tracked_fit_transform(self, X, *args, **kwargs):
        result = _original_fit_transform(self, X, *args, **kwargs)
        arr = np.asarray(result)
        record = {
            "input_shape": list(np.asarray(X).shape),
            "output_shape": list(arr.shape),
            "finite": bool(np.isfinite(arr).all()),
            "nonnegative": bool((arr >= -1e-12).all())
        }
        with open("/tmp/verifier_nmf_trace.jsonl", "a") as f:
            f.write(json.dumps(record) + "\n")
        return result
    sklearn.decomposition.NMF.fit_transform = _tracked_fit_transform
except Exception:
    pass
'''
    with open(os.path.join(instrument_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env["PYTHONPATH"] = instrument_dir + os.pathsep + "/home/user"
    process = subprocess.Popen(
        [sys.executable, "/app/services/worker/worker.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        preexec_fn=os.setsid,
    )

    rng = np.random.default_rng(424242)
    base = rng.random(10)
    evil = np.tile(base, (10, 1)) + rng.normal(0, 1e-8, (10, 10))
    clean = rng.uniform(0.1, 1.0, (10, 10))

    def csv_bytes(mat):
        return "\n".join(",".join(map(str, row)) for row in mat)

    try:
        client.lpush("spectra_queue", csv_bytes(evil))
        assert wait_for(lambda: len(read_json_lines(filter_trace)) >= 1, timeout=10), \
            "The worker did not invoke check_matrix for an incoming matrix."
        time.sleep(1)
        assert process.poll() is None, "The worker crashed while handling a rejected matrix."
        first_calls = read_json_lines(filter_trace)
        assert first_calls[0]["result"] is False, "The worker's filter did not reject the evil matrix."
        assert not read_json_lines(nmf_trace), "The worker passed a rejected matrix to NMF."
        assert not os.path.exists(log_path) or not open(log_path).read().strip(), \
            "The worker logged a rejected matrix as a successful extraction."

        client.lpush("spectra_queue", csv_bytes(clean))
        assert wait_for(lambda: len(read_json_lines(filter_trace)) >= 2, timeout=10), \
            "The worker did not invoke check_matrix for the clean matrix."
        assert wait_for(lambda: len(read_json_lines(nmf_trace)) >= 1, timeout=10), \
            "The worker did not run NMF on the accepted clean matrix."
        assert wait_for(lambda: os.path.exists(log_path) and bool(open(log_path).read().strip()), timeout=5), \
            "The worker did not log the successful extraction."
        assert process.poll() is None, "The worker crashed after processing the clean matrix."

        calls = read_json_lines(filter_trace)
        assert calls[1]["result"] is True, "The worker's filter rejected the clean matrix."
        nmf_records = read_json_lines(nmf_trace)
        assert len(nmf_records) == 1, "Unexpected number of NMF executions."
        result = nmf_records[0]
        assert result["input_shape"] == [10, 10], "NMF received an unexpected matrix."
        assert len(result["output_shape"]) == 2 and result["output_shape"][0] == 10 and result["output_shape"][1] > 0
        assert result["finite"], "NMF produced non-finite features."
        assert result["nonnegative"], "NMF produced negative features."
    finally:
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except Exception:
            pass
        try:
            process.wait(timeout=3)
        except Exception:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except Exception:
                pass
        client.flushdb()


def test_end_to_end_flow():
    start_script = "/app/services/start.sh"
    assert os.path.isfile(start_script), f"Start script {start_script} is missing."

    log_path = "/app/services/worker/success.log"
    if os.path.exists(log_path):
        os.remove(log_path)

    subprocess.run(["redis-server", "--daemonize", "yes"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    client = redis.Redis(host="localhost", port=6379)
    assert wait_for(lambda: client.ping(), timeout=5)
    client.flushdb()

    # Seed enough valid work to make the original three-success assertion deterministic.
    rng = np.random.default_rng(112233)
    for _ in range(4):
        mat = rng.uniform(0.1, 1.0, (10, 10))
        csv_data = "\n".join(",".join(map(str, row)) for row in mat)
        client.lpush("spectra_queue", csv_data)

    process = subprocess.Popen([start_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               preexec_fn=os.setsid)
    try:
        def three_lines():
            if not os.path.isfile(log_path):
                return False
            with open(log_path, "r") as f:
                return len([line for line in f.read().splitlines() if line.strip()]) >= 3

        assert wait_for(three_lines, timeout=10), \
            f"Expected at least 3 entries in {log_path}, but they were not produced."
        assert os.path.isfile(log_path), f"Success log {log_path} was not created. The worker might have crashed or failed."
        with open(log_path, "r") as f:
            lines = [line for line in f.read().splitlines() if line.strip()]
        assert len(lines) >= 3, f"Expected at least 3 entries in {log_path}, but found {len(lines)}."
        assert process.poll() is None, "The service pipeline terminated unexpectedly."
    finally:
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except Exception:
            pass
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
