#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import signal
import subprocess
import time
import urllib.request

import numpy as np
import pytest
from scipy import stats


def test_files_exist():
    """Verify that all required files exist."""
    expected_files = [
        "/home/user/api.py",
        "/home/user/benchmark.sh",
        "/home/user/analyze.py",
        "/home/user/latencies_1.txt",
        "/home/user/latencies_4.txt",
        "/home/user/results.json",
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"File {f} is missing."


def test_benchmark_executable():
    """Verify that the benchmark script is executable."""
    assert os.access("/home/user/benchmark.sh", os.X_OK), "/home/user/benchmark.sh is not executable."


def _post_search(query):
    req = urllib.request.Request(
        "http://127.0.0.1:8000/search",
        data=json.dumps({"query": [float(x) for x in query]}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        return json.loads(response.read().decode("utf-8"))


def _expected_top(vectors, query):
    q = np.asarray(query, dtype=np.float64)
    a = vectors.astype(np.float64, copy=False)
    scores = (a @ q) / (np.linalg.norm(a, axis=1) * np.linalg.norm(q))
    return np.argsort(-scores)[:5].astype(int).tolist()


def test_api_logic():
    """Verify that the API correctly computes cosine similarity for derived queries."""
    proc = subprocess.Popen(
        ["python3", "/home/user/api.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 15
        while True:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f"API exited before becoming ready:\n{out.decode(errors='replace')}\n{err.decode(errors='replace')}")
            try:
                with urllib.request.urlopen("http://127.0.0.1:8000/", timeout=0.3):
                    pass
            except Exception:
                pass
            try:
                vectors = np.load("/home/user/vectors.npy")
                first = _post_search(vectors[42])
                break
            except Exception:
                if time.time() >= deadline:
                    pytest.fail("API did not become ready on 127.0.0.1:8000")
                time.sleep(0.1)

        assert "top_indices" in first, "API response is missing the 'top_indices' key."
        assert len(first["top_indices"]) == 5, f"Expected 5 top indices, got {len(first['top_indices'])}."
        assert first["top_indices"][0] == 42, f"Expected the first index to be 42, got {first['top_indices'][0]}."
        assert first["top_indices"] == _expected_top(vectors, vectors[42])

        rng = np.random.default_rng(918273)
        queries = [
            rng.normal(size=100),
            0.65 * vectors[137].astype(np.float64) + 0.35 * vectors[2941].astype(np.float64),
            rng.uniform(-2.0, 2.0, size=100),
        ]
        for query in queries:
            data = _post_search(query)
            assert set(data) == {"top_indices"}, f"Unexpected API response: {data}"
            assert isinstance(data["top_indices"], list) and len(data["top_indices"]) == 5
            assert all(isinstance(i, int) and not isinstance(i, bool) for i in data["top_indices"])
            assert data["top_indices"] == _expected_top(vectors, query)
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=5)


def _descendants(root_pid):
    parents = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/status") as f:
                ppid = None
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                        break
            parents[int(name)] = ppid
        except (OSError, ValueError):
            pass
    found = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parents.items():
            if ppid in found and pid not in found:
                found.add(pid)
                changed = True
    found.discard(root_pid)
    return found


def _read_proc(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmd = f.read().replace(b"\0", b" ").decode(errors="replace").lower()
        with open(f"/proc/{pid}/environ", "rb") as f:
            env_items = f.read().split(b"\0")
        env = {}
        for item in env_items:
            if b"=" in item:
                k, v = item.split(b"=", 1)
                env[k.decode(errors="replace")] = v.decode(errors="replace")
        return cmd, env
    except OSError:
        return "", {}


def _load_latency_file(path):
    with open(path) as f:
        lines = [line.strip() for line in f]
    assert len(lines) == 200, f"{path} must contain exactly 200 latency lines, got {len(lines)}"
    assert all(line and len(line.split()) == 1 for line in lines), f"{path} must contain one float per line"
    try:
        values = np.asarray([float(line) for line in lines], dtype=float)
    except ValueError as exc:
        pytest.fail(f"{path} contains a non-float latency: {exc}")
    assert np.all(np.isfinite(values)), f"{path} contains non-finite values"
    assert np.all(values > 0), f"{path} contains non-positive latencies"
    assert np.ptp(values) > 0, f"{path} does not contain measured, varying latencies"
    return values


def test_benchmark_pipeline():
    """Execute the benchmark and validate both runs and their fresh raw outputs."""
    for path in ("/home/user/latencies_1.txt", "/home/user/latencies_4.txt"):
        os.unlink(path)

    proc = subprocess.Popen(
        ["/home/user/benchmark.sh"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    observed_threads = set()
    deadline = time.time() + 300
    try:
        while proc.poll() is None:
            for pid in _descendants(proc.pid):
                cmd, env = _read_proc(pid)
                server_process = "api.py" in cmd or "uvicorn" in cmd or ("flask" in cmd and "api" in cmd)
                if server_process and env.get("OMP_NUM_THREADS") in {"1", "4"}:
                    observed_threads.add(env["OMP_NUM_THREADS"])
            if time.time() >= deadline:
                os.killpg(proc.pid, signal.SIGKILL)
                pytest.fail("benchmark.sh timed out after 300 seconds")
            time.sleep(0.01)
        out, err = proc.communicate(timeout=5)
    finally:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    assert proc.returncode == 0, f"benchmark.sh failed:\n{out.decode(errors='replace')}\n{err.decode(errors='replace')}"
    assert observed_threads == {"1", "4"}, f"Did not observe API runs with both OMP_NUM_THREADS=1 and 4: {observed_threads}"
    assert os.path.isfile("/home/user/latencies_1.txt")
    assert os.path.isfile("/home/user/latencies_4.txt")
    _load_latency_file("/home/user/latencies_1.txt")
    _load_latency_file("/home/user/latencies_4.txt")


def test_analysis_pipeline():
    """Exercise analyze.py on verifier-derived data and compare every statistic."""
    one = np.asarray([1.10, 1.35, 0.95, 1.60, 1.25, 1.42, 1.05, 1.31, 1.18], dtype=float)
    four = np.asarray([0.72, 0.91, 0.80, 1.02, 0.77, 0.86, 0.69, 0.94, 0.83, 0.75, 0.89], dtype=float)
    np.savetxt("/home/user/latencies_1.txt", one, fmt="%.12g")
    np.savetxt("/home/user/latencies_4.txt", four, fmt="%.12g")
    try:
        os.unlink("/home/user/results.json")
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        ["python3", "/home/user/analyze.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "analyze.py failed:\n"
        + completed.stdout.decode(errors="replace")
        + "\n"
        + completed.stderr.decode(errors="replace")
    )
    assert os.path.isfile("/home/user/results.json"), "analyze.py did not create results.json"

    with open("/home/user/results.json") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/results.json is not valid JSON.")

    expected_keys = {"mean_1", "mean_4", "p_value", "ci_lower", "ci_upper", "significant"}
    assert set(data.keys()) == expected_keys, f"Expected keys {expected_keys}, got {set(data.keys())}"
    for key in ("mean_1", "mean_4", "p_value", "ci_lower", "ci_upper"):
        assert isinstance(data[key], (int, float)), f"{key} must be a float"
        assert not isinstance(data[key], bool), f"{key} must not be boolean"
        assert math.isfinite(data[key]), f"{key} must be finite"
    assert isinstance(data["significant"], bool), "significant must be a boolean"

    t_result = stats.ttest_ind(one, four, equal_var=False)
    mean_1 = float(np.mean(one))
    mean_4 = float(np.mean(four))
    v1 = float(np.var(one, ddof=1))
    v4 = float(np.var(four, ddof=1))
    a = v1 / len(one)
    b = v4 / len(four)
    se = math.sqrt(a + b)
    df = (a + b) ** 2 / (a * a / (len(one) - 1) + b * b / (len(four) - 1))
    margin = float(stats.t.ppf(0.975, df)) * se
    expected = {
        "mean_1": mean_1,
        "mean_4": mean_4,
        "p_value": float(t_result.pvalue),
        "ci_lower": mean_1 - mean_4 - margin,
        "ci_upper": mean_1 - mean_4 + margin,
    }
    for key, value in expected.items():
        assert math.isclose(float(data[key]), value, rel_tol=1e-7, abs_tol=1e-10), (
            f"Incorrect {key}: expected {value}, got {data[key]}"
        )
    assert data["significant"] is (expected["p_value"] < 0.05)


def test_results_json_schema():
    """Retain the original final schema and broad type assertions."""
    with open("/home/user/results.json", "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/results.json is not valid JSON.")

    expected_keys = {"mean_1", "mean_4", "p_value", "ci_lower", "ci_upper", "significant"}
    assert set(data.keys()) == expected_keys, f"Expected keys {expected_keys}, got {set(data.keys())}"
    assert isinstance(data["mean_1"], (int, float)), "mean_1 must be a float"
    assert isinstance(data["mean_4"], (int, float)), "mean_4 must be a float"
    assert isinstance(data["p_value"], (int, float)), "p_value must be a float"
    assert isinstance(data["ci_lower"], (int, float)), "ci_lower must be a float"
    assert isinstance(data["ci_upper"], (int, float)), "ci_upper must be a float"
    assert isinstance(data["significant"], bool), "significant must be a boolean"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
