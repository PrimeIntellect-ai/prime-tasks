#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import time
import uuid

import pytest

HOME = "/home/user"
ENGINE = f"{HOME}/src/sim_engine"
WORKER = f"{ENGINE}/worker"
FILTER = f"{HOME}/bin/filter_trajectories"
LATEST = f"{HOME}/data/latest"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, **kwargs)


def parse_config(path):
    values = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].strip()
            if "=" in line:
                key, value = line.split("=", 1)
                values[key.strip().lower()] = value.strip().strip("'\"")
    return values


def file_state():
    state = {}
    for path in glob.glob(os.path.join(LATEST, "*.csv")):
        if os.path.isfile(path):
            with open(path, "rb") as f:
                data = f.read()
            st = os.stat(path)
            state[path] = (st.st_mtime_ns, st.st_size, hashlib.sha256(data).hexdigest())
    return state


def wait_for_csv_change(before, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        current = file_state()
        changed = [p for p, state in current.items() if p not in before or before[p] != state]
        if changed:
            time.sleep(0.3)
            result = {}
            for path in changed:
                if os.path.exists(path):
                    with open(path, "rb") as f:
                        result[path] = f.read()
            if result:
                return result
        time.sleep(0.2)
    pytest.fail("POST /generate did not create or update a CSV trajectory in /home/user/data/latest")


def numeric_trajectory(data):
    text = data.decode("utf-8")
    rows = list(csv.reader(text.splitlines()))
    assert len(rows) >= 3, "Generated trajectory must contain a header and at least two samples"
    assert len(rows[0]) >= 2, "Generated trajectory has too few columns"
    width = len(rows[0])
    result = []
    for row in rows[1:]:
        assert len(row) == width, "Generated CSV has inconsistent row widths"
        converted = []
        for cell in row:
            value = float(cell)
            assert value == value and abs(value) != float("inf"), "Generated trajectory contains NaN or infinity"
            converted.append(cell.strip())
        result.append(tuple(converted))
    return tuple(result)


def worker_is_running():
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            exe = os.path.join(proc, "exe")
            if os.path.samefile(exe, WORKER):
                return True
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return False


@pytest.fixture(scope="session")
def services():
    api_cfg = parse_config(f"{HOME}/config/api.env")
    worker_cfg = parse_config(f"{HOME}/config/worker.conf")

    host = api_cfg.get("redis_host")
    port = api_cfg.get("redis_port")
    assert host in {"localhost", "127.0.0.1"}, "API REDIS_HOST must point to the local Redis instance"
    assert port == "6379", "API REDIS_PORT must be 6379"

    api_queues = [v for k, v in api_cfg.items() if "queue" in k]
    worker_queues = [v for k, v in worker_cfg.items() if "queue" in k]
    assert api_queues, "API configuration does not define its Redis job queue"
    assert worker_queues, "Worker configuration does not define its Redis job queue"
    assert set(api_queues).intersection(worker_queues), "API and worker are configured for different Redis queues"
    assert "wrong_queue" not in api_queues + worker_queues, "Placeholder queue configuration was not fixed"

    main_path = f"{ENGINE}/main.cpp"
    solver_path = f"{ENGINE}/ode_solver.cpp"
    makefile = f"{ENGINE}/Makefile"
    for path in (main_path, solver_path, makefile):
        assert os.path.isfile(path), f"Missing engine source/build file: {path}"
    with open(main_path, encoding="utf-8", errors="replace") as f:
        main_source = f.read()
    with open(solver_path, encoding="utf-8", errors="replace") as f:
        solver_source = f.read()
    combined = main_source + "\n" + solver_source
    assert "ODE Solver with reduction issue" not in solver_source, "The placeholder ODE solver was not implemented"
    assert len(combined) > 300 and re.search(r"\b(double|long double|float)\b", combined), "C++ sources do not contain a numerical simulation implementation"
    assert not re.search(r"#\s*pragma\s+omp\s+parallel\s+for[^\n]*reduction\s*\(", combined, re.I), "Order-dependent OpenMP floating-point reduction remains in the source"

    if os.path.exists(WORKER):
        os.remove(WORKER)
    built = run(["make", "-B"], cwd=ENGINE, timeout=60)
    assert built.returncode == 0, f"Engine failed to compile from source\nstdout:\n{built.stdout}\nstderr:\n{built.stderr}"
    assert os.path.isfile(WORKER) and os.access(WORKER, os.X_OK), "Makefile did not produce an executable worker"
    with open(WORKER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled worker is not a native executable"

    startup = f"{HOME}/start_services.sh"
    assert os.path.isfile(startup) and os.access(startup, os.X_OK), "start_services.sh is missing or not executable"
    subprocess.Popen([startup], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    deadline = time.time() + 20
    redis_ok = api_ok = False
    while time.time() < deadline:
        ping = run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "ping"], timeout=3)
        redis_ok = ping.returncode == 0 and ping.stdout.strip() == "PONG"
        probe = run(["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "http://127.0.0.1:5000/"], timeout=3)
        api_ok = probe.returncode == 0 and probe.stdout.strip() not in {"000", ""}
        if redis_ok and api_ok and worker_is_running():
            break
        time.sleep(0.25)

    assert redis_ok, "Redis is not reachable on localhost:6379 after start_services.sh"
    assert api_ok, "Flask API is not reachable on localhost:5000 after start_services.sh"
    assert worker_is_running(), "The freshly compiled C++ worker is not running"

    key = "verifier_connectivity_" + uuid.uuid4().hex
    put = run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "SET", key, "connected"], timeout=3)
    get = run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "GET", key], timeout=3)
    run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "DEL", key], timeout=3)
    assert put.returncode == 0 and get.stdout.strip() == "connected", "Redis state-store round trip failed"
    return True


def test_pipeline_status_log():
    log_path = "/home/user/pipeline_status.log"
    assert os.path.exists(log_path), f"Missing pipeline status log: {log_path}"
    with open(log_path, "r") as f:
        content = f.read()
    assert "PIPELINE_SUCCESS" in content, "Pipeline status log does not contain 'PIPELINE_SUCCESS'"


def test_filter_trajectories_executable():
    assert os.path.exists(FILTER), f"Missing executable: {FILTER}"
    assert os.path.isfile(FILTER), f"Not a regular file: {FILTER}"
    assert os.access(FILTER, os.X_OK), f"File is not executable: {FILTER}"


def test_original_corpus_assertions():
    evil_corpus_dir = "/app/data/corpus/evil"
    clean_corpus_dir = "/app/data/corpus/clean"
    assert os.path.isdir(evil_corpus_dir), f"Missing evil corpus: {evil_corpus_dir}"
    assert os.path.isdir(clean_corpus_dir), f"Missing clean corpus: {clean_corpus_dir}"
    evil_files = set(os.listdir(evil_corpus_dir))
    clean_files = set(os.listdir(clean_corpus_dir))
    with tempfile.TemporaryDirectory() as temp_dir:
        for f in evil_files:
            shutil.copy(os.path.join(evil_corpus_dir, f), os.path.join(temp_dir, f))
        for f in clean_files:
            shutil.copy(os.path.join(clean_corpus_dir, f), os.path.join(temp_dir, f))
        result = run([FILTER, temp_dir], timeout=30)
        assert result.returncode == 0, f"filter_trajectories failed\nstdout: {result.stdout}\nstderr: {result.stderr}"
        remaining = set(os.listdir(temp_dir))
        assert not evil_files.intersection(remaining), "Evil corpus files bypassed the filter"
        assert not clean_files.difference(remaining), "Clean corpus files were deleted"


def test_generated_adversarial_corpus():
    with tempfile.TemporaryDirectory() as temp_dir:
        fixtures = {
            "clean_constant.csv": "time,theta,omega,energy\n0,1,0,5.0000000000000000\n1,0.9,-0.1,5.0000000000000000\n2,0.8,-0.2,5.0000000000000000\n",
            "clean_tolerance.csv": "time,theta,omega,energy\n0,1,0,2.0000000000000\n1,0.9,-0.1,2.0000000000005\n2,0.8,-0.2,1.9999999999996\n",
            "evil_positive_drift.csv": "time,theta,omega,energy\n0,1,0,3.0000000000000\n1,0.9,-0.1,3.0000000000021\n2,0.8,-0.2,3.0000000000030\n",
            "evil_negative_drift.csv": "time,theta,omega,energy\n0,1,0,7.0000000000000\n1,0.9,-0.1,6.9999999999978\n2,0.8,-0.2,6.9999999999970\n",
            "README.txt": "This non-CSV file must remain unchanged.\n",
        }
        for name, content in fixtures.items():
            with open(os.path.join(temp_dir, name), "w", encoding="utf-8") as f:
                f.write(content)
        before = {name: hashlib.sha256(content.encode()).hexdigest() for name, content in fixtures.items()}
        result = run([FILTER, temp_dir], timeout=30)
        assert result.returncode == 0, f"filter_trajectories failed\nstdout: {result.stdout}\nstderr: {result.stderr}"
        for name in ("evil_positive_drift.csv", "evil_negative_drift.csv"):
            assert not os.path.exists(os.path.join(temp_dir, name)), f"Corrupt trajectory was not deleted: {name}"
        for name in ("clean_constant.csv", "clean_tolerance.csv", "README.txt"):
            path = os.path.join(temp_dir, name)
            assert os.path.isfile(path), f"Clean/non-CSV file was deleted: {name}"
            with open(path, "rb") as f:
                assert hashlib.sha256(f.read()).hexdigest() == before[name], f"File was modified: {name}"


def test_end_to_end_generation_and_determinism(services):
    os.makedirs(LATEST, exist_ok=True)
    before_first = file_state()
    first_request = run(["curl", "-sS", "-X", "POST", "-o", "/tmp/generate_first.out", "-w", "%{http_code}", "http://127.0.0.1:5000/generate"], timeout=10)
    assert first_request.returncode == 0, f"First POST /generate failed: {first_request.stderr}"
    assert first_request.stdout.strip().startswith("2"), f"First POST /generate returned HTTP {first_request.stdout.strip()}"
    first_outputs = wait_for_csv_change(before_first)
    first_numeric = [numeric_trajectory(data) for data in first_outputs.values()]

    before_second = file_state()
    first_saved = dict(first_outputs)
    second_request = run(["curl", "-sS", "-X", "POST", "-o", "/tmp/generate_second.out", "-w", "%{http_code}", "http://127.0.0.1:5000/generate"], timeout=10)
    assert second_request.returncode == 0, f"Second POST /generate failed: {second_request.stderr}"
    assert second_request.stdout.strip().startswith("2"), f"Second POST /generate returned HTTP {second_request.stdout.strip()}"
    second_outputs = wait_for_csv_change(before_second)
    second_numeric = [numeric_trajectory(data) for data in second_outputs.values()]
    assert any(a == b for a in first_numeric for b in second_numeric), "Identical generation requests did not produce bit-for-bit identical numeric trajectories"

    with tempfile.TemporaryDirectory() as temp_dir:
        for index, data in enumerate(first_saved.values()):
            with open(os.path.join(temp_dir, f"generated_{index}.csv"), "wb") as f:
                f.write(data)
        expected = {p: open(os.path.join(temp_dir, p), "rb").read() for p in os.listdir(temp_dir)}
        filtered = run([FILTER, temp_dir], timeout=30)
        assert filtered.returncode == 0, f"Filter failed on generated trajectories: {filtered.stderr}"
        for name, data in expected.items():
            path = os.path.join(temp_dir, name)
            assert os.path.isfile(path), "The filter classified a freshly generated trajectory as corrupt"
            with open(path, "rb") as f:
                assert f.read() == data, "The filter modified a freshly generated trajectory"

    assert worker_is_running(), "C++ worker stopped while processing generation jobs"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
