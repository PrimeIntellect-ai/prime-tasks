#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_pipeline.py
import itertools
import json
import math
import os
import secrets
import signal
import socket
import subprocess
import time

import requests

API = "http://127.0.0.1:9000/prepare_training_data"
TOKEN = {"Authorization": "Bearer ml_prep_token_2024"}


def kill_port(port):
    inodes = set()
    target = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == target and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=.15):
                time.sleep(.1)
        except OSError:
            return
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_port(port, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=.3):
                return
        except OSError:
            time.sleep(.2)
    raise AssertionError(f"service on port {port} did not start")


def make_pdb(pdb_id, multipliers):
    scale = (70 + secrets.randbelow(111)) / 100.0
    distances = [round(scale * x, 3) for x in multipliers]
    xs = [round((secrets.randbelow(500) - 250) / 100.0, 3)]
    for d in distances:
        xs.append(round(xs[-1] + d, 3))
    path = f"/app/data/{pdb_id}.pdb"
    with open(path, "w") as f:
        for i, x in enumerate(xs, 1):
            f.write(f"ATOM  {i:5d}  CA  ALA A{i:4d}    {x:8.3f}{0.0:8.3f}{0.0:8.3f}  1.00  0.00           C  \n")
    return path


def expected_values(path):
    coords = []
    with open(path) as f:
        for line in f:
            if line.startswith("ATOM  ") and line[12:16].strip() == "CA":
                coords.append(tuple(float(line[a:b]) for a, b in ((30, 38), (38, 46), (46, 54))))
    assert len(coords) >= 3
    distances = [math.dist(coords[i - 1], coords[i]) for i in range(1, len(coords))]
    smooth = []
    for i, value in enumerate(distances):
        smooth.append((distances[max(0, i - 1)] + value + distances[min(len(distances) - 1, i + 1)]) / 3.0)
    mean = sum(smooth) / len(smooth)

    # Exact bootstrap distribution for this small signal. This is derived from
    # the verifier-created input rather than from fixed expected constants.
    n = len(smooth)
    means = sorted(sum(sample) / n for sample in itertools.product(smooth, repeat=n))
    lo = means[int(.025 * (len(means) - 1))]
    hi = means[int(.975 * (len(means) - 1))]
    return mean, lo, hi, max(smooth) - min(smooth)


def post(pdb_id, samples=15000, headers=TOKEN, timeout=35):
    return requests.post(API, json={"pdb_id": pdb_id, "num_bootstrap_samples": samples}, headers=headers, timeout=timeout)


def assert_result(response, expected):
    assert response.status_code == 200, response.text
    data = response.json()
    assert data.get("status") == "success"
    for key in ("mean", "ci_lower", "ci_upper"):
        assert key in data and isinstance(data[key], (int, float)) and math.isfinite(data[key])
    mean, lo, hi, spread = expected
    assert math.isclose(data["mean"], mean, rel_tol=1e-5, abs_tol=1e-6)
    assert data["ci_lower"] < data["mean"] < data["ci_upper"]
    tolerance = max(.04, spread * .08)
    assert abs(data["ci_lower"] - lo) <= tolerance, (data, expected)
    assert abs(data["ci_upper"] - hi) <= tolerance, (data, expected)
    return data


def test_complete_pipeline():
    assert os.path.isfile("/home/user/pipeline/main.go"), "main.go is missing"
    assert os.path.isfile("/home/user/start_all.sh"), "start_all.sh is missing"

    # Confirm the submitted Go source actually contains a goroutine statement,
    # using Go's parser so comments and strings cannot satisfy the check.
    checker = r'''
package main
import ("go/ast"; "go/parser"; "go/token"; "os")
func main() {
 f, e := parser.ParseFile(token.NewFileSet(), "/home/user/pipeline/main.go", nil, 0)
 if e != nil { os.Exit(2) }
 found := false
 ast.Inspect(f, func(n ast.Node) bool { if _, ok := n.(*ast.GoStmt); ok { found = true }; return true })
 if !found { os.Exit(1) }
}
'''
    with open("/tmp/check_goroutine.go", "w") as f:
        f.write(checker)
    result = subprocess.run(["go", "run", "/tmp/check_goroutine.go"], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, "main.go must use goroutines for parallel bootstrap work"

    # Remove any services left running by the agent, then require start_all.sh
    # itself to bring up all three services.
    for port in (9000, 8080, 6379):
        kill_port(port)
    result = subprocess.run(["bash", "/home/user/start_all.sh"], stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=12)
    assert result.returncode == 0, "start_all.sh failed or did not background all services"
    for port in (6379, 8080, 9000):
        wait_port(port)

    # Inputs and IDs are generated only after the submitted services have
    # started, preventing a fixed-ID/fixed-answer implementation.
    id1 = "T" + secrets.token_hex(4).upper()
    id2 = "U" + secrets.token_hex(4).upper()
    path1 = make_pdb(id1, [1.0, 4.0, 2.0, 8.0, 3.0, 7.0])
    path2 = make_pdb(id2, [6.0, 1.5, 5.0, 2.5, 9.0, 4.0])

    assert requests.get(f"http://127.0.0.1:8080/{id1}.pdb", timeout=5).status_code == 200

    assert post(id1, 100, headers={}).status_code == 401
    assert post(id1, 100, headers={"Authorization": "Bearer wrong"}).status_code == 401

    subprocess.run(["redis-cli", "FLUSHDB"], check=True, stdout=subprocess.DEVNULL, timeout=5)
    data1 = assert_result(post(id1), expected_values(path1))

    cached = subprocess.check_output(
        ["redis-cli", "--raw", "GET", f"spectro_ci_{id1}"], text=True, timeout=5
    ).strip()
    ci = json.loads(cached)
    assert isinstance(ci, list) and len(ci) == 2
    assert all(isinstance(x, (int, float)) and math.isfinite(x) for x in ci)
    assert math.isclose(ci[0], data1["ci_lower"], rel_tol=1e-9, abs_tol=1e-9)
    assert math.isclose(ci[1], data1["ci_upper"], rel_tol=1e-9, abs_tol=1e-9)

    # A never-requested dynamic ID must fail while the raw HTTP service is
    # unavailable. This rejects implementations that read /app/data directly
    # or fabricate results without performing the required HTTP fetch.
    kill_port(8080)
    try:
        unavailable = post(id2, 500, timeout=12)
        assert unavailable.status_code != 200, "request succeeded even though the raw data server was down"
    except requests.RequestException:
        pass

    raw = subprocess.Popen(
        ["python3", "-m", "http.server", "8080", "--bind", "127.0.0.1", "--directory", "/app/data"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        wait_port(8080, 8)
        subprocess.run(["redis-cli", "DEL", f"spectro_ci_{id2}"], check=True,
                       stdout=subprocess.DEVNULL, timeout=5)
        data2 = assert_result(post(id2), expected_values(path2))
        cached2 = json.loads(subprocess.check_output(
            ["redis-cli", "--raw", "GET", f"spectro_ci_{id2}"], text=True, timeout=5
        ).strip())
        assert len(cached2) == 2
        assert math.isclose(cached2[0], data2["ci_lower"], rel_tol=1e-9, abs_tol=1e-9)
        assert math.isclose(cached2[1], data2["ci_upper"], rel_tol=1e-9, abs_tol=1e-9)
    finally:
        raw.terminate()
PYTEST

if python3 -m pytest /tmp/test_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
