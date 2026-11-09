#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import signal
import subprocess
import tempfile
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
SCRIPT_PATH = "/home/user/setup_and_run.sh"
VENV_PATH = "/home/user/venv"


def wait_for_service(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(f"{BASE_URL}/top?n=1", timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


def listener_pids(port=8080):
    inodes = set()
    target_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if local.rsplit(":", 1)[-1].upper() == target_port and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_service():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope="session", autouse=True)
def deploy_with_submitted_script():
    assert os.path.exists(SCRIPT_PATH), f"Deployment script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Deployment script {SCRIPT_PATH} is not executable."

    stop_service()

    backup = VENV_PATH + ".verifier_backup"
    if os.path.exists(backup):
        shutil.rmtree(backup)
    if os.path.exists(VENV_PATH):
        os.rename(VENV_PATH, backup)

    proc = subprocess.Popen(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        rc = proc.wait(timeout=120)
    except subprocess.TimeoutExpired:
        proc.kill()
        pytest.fail("Deployment script did not return after starting the service in the background.")
    assert rc == 0, f"Deployment script exited with status {rc}."

    assert os.path.isfile(os.path.join(VENV_PATH, "pyvenv.cfg")), \
        "Deployment script did not create a Python virtual environment at /home/user/venv."
    venv_python = os.path.join(VENV_PATH, "bin", "python")
    assert os.path.exists(venv_python) and os.access(venv_python, os.X_OK), \
        "The created virtual environment has no executable Python interpreter."
    prefix = subprocess.check_output(
        [venv_python, "-c", "import sys; print(sys.prefix)"], text=True
    ).strip()
    assert os.path.realpath(prefix) == os.path.realpath(VENV_PATH), \
        "The interpreter under /home/user/venv is not a working virtual environment."

    assert wait_for_service(), f"Service at {BASE_URL} is not responding after running the deployment script."

    # Activation exports VIRTUAL_ENV to the service process. This also ensures the
    # freshly-created environment, rather than an unrelated global interpreter,
    # was used to launch the submitted service.
    activated = False
    for pid in listener_pids():
        try:
            env = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
        except (FileNotFoundError, PermissionError):
            continue
        if f"VIRTUAL_ENV={VENV_PATH}".encode() in env:
            activated = True
            break
    assert activated, "The listening service was not launched from the activated /home/user/venv environment."

    if os.path.exists(backup):
        shutil.rmtree(backup)

    yield


def test_setup_script_exists_and_executable():
    script_path = "/home/user/setup_and_run.sh"
    assert os.path.exists(script_path), f"Deployment script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Deployment script {script_path} is not executable."


def test_analyze_endpoint():
    payload = {
        "files": [
            "/app/file_high_entropy.bin",
            "/app/file_low_entropy.txt",
            "/app/file_tiny.txt",
            "/app/non_existent_file.xyz"
        ]
    }
    resp = requests.post(f"{BASE_URL}/analyze", json=payload)
    assert resp.status_code == 200, f"Expected status code 200, got {resp.status_code}. Response: {resp.text}"

    data = resp.json()
    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert data.get("processed") == 3, f"Expected 3 valid files processed, got {data.get('processed')}"


def test_top_endpoint_ranking():
    resp = requests.get(f"{BASE_URL}/top?n=2")
    assert resp.status_code == 200, f"Expected status code 200, got {resp.status_code}. Response: {resp.text}"

    data = resp.json()
    assert isinstance(data, list), "Expected a JSON list from /top"
    assert len(data) == 2, f"Expected 2 items, got {len(data)}"

    assert data[0]["path"] == "/app/file_high_entropy.bin", f"Expected high entropy file first, got {data[0]['path']}"
    assert data[1]["path"] == "/app/file_low_entropy.txt", f"Expected low entropy file second, got {data[1]['path']}"
    assert data[0]["pcf"] >= data[1]["pcf"], "Expected PCF to be in descending order"


def test_pcf_computation_logic():
    resp = requests.get(f"{BASE_URL}/top?n=3")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 3

    tiny_path = "/app/file_tiny.txt"
    tiny_item = next((item for item in data if item["path"] == tiny_path), None)
    assert tiny_item is not None, f"Could not find {tiny_path} in /top results"

    out = subprocess.check_output(["/app/legacy_scorer", tiny_path])
    entropy = float(out.strip())
    size = os.path.getsize(tiny_path)
    expected_pcf = entropy * math.log2(max(size, 2))

    actual_pcf = tiny_item["pcf"]
    assert math.isclose(actual_pcf, expected_pcf, rel_tol=1e-3), \
        f"PCF computation mismatch for {tiny_path}. Expected ~{expected_pcf}, got {actual_pcf}"


def test_runtime_generated_files_general_scoring_ties_and_nonremoving_top():
    workdir = tempfile.mkdtemp(prefix="pcf_runtime_")
    paths = []
    try:
        # Contents and names are generated only when verification runs, so a fixed
        # response cannot know their paths or scores in advance.
        for i, size in enumerate((2, 3, 17, 31, 64, 129, 257)):
            path = os.path.join(workdir, f"random_{i}_{os.urandom(5).hex()}.bin")
            with open(path, "wb") as f:
                f.write(os.urandom(size))
            paths.append(path)

        tie_bytes = os.urandom(73)
        tie_a = os.path.join(workdir, "tie_alpha.bin")
        tie_b = os.path.join(workdir, "tie_beta.bin")
        for path in (tie_a, tie_b):
            with open(path, "wb") as f:
                f.write(tie_bytes)
            paths.append(path)

        missing = os.path.join(workdir, "missing_" + os.urandom(6).hex())

        # Temporarily wrap the supplied scorer to prove the service invokes it for
        # each arbitrary valid file rather than returning precomputed scores.
        scorer = "/app/legacy_scorer"
        real_scorer = "/app/legacy_scorer.verifier-real"
        call_log = os.path.join(workdir, "scorer_calls.log")
        open(call_log, "w").close()
        os.chmod(call_log, 0o666)
        os.rename(scorer, real_scorer)
        try:
            with open(scorer, "w") as f:
                f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" >> " + call_log + "\nexec " + real_scorer + " \"$1\"\n")
            os.chmod(scorer, 0o755)

            resp = requests.post(
                f"{BASE_URL}/analyze",
                json={"files": paths + [missing]},
                timeout=30,
            )
        finally:
            if os.path.exists(scorer):
                os.unlink(scorer)
            os.rename(real_scorer, scorer)

        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body.get("status") == "success"
        assert body.get("processed") == len(paths), \
            "All runtime-created files must be processed and the nonexistent file skipped."

        with open(call_log) as f:
            calls = [line.rstrip("\n") for line in f]
        for path in paths:
            assert path in calls, f"The service did not invoke /app/legacy_scorer for {path}."
        assert missing not in calls, "The scorer should not be invoked for a nonexistent file."

        expected = {}
        for path in paths:
            entropy = float(subprocess.check_output([scorer, path], text=True).strip())
            expected[path] = entropy * math.log2(max(os.path.getsize(path), 2))

        first = requests.get(f"{BASE_URL}/top?n=10000", timeout=10)
        assert first.status_code == 200, first.text
        data = first.json()
        assert isinstance(data, list)
        assert all(isinstance(item, dict) and "path" in item and "pcf" in item for item in data)

        by_path = {item["path"]: item for item in data}
        for path, wanted in expected.items():
            assert path in by_path, f"Analyzed runtime file {path} is absent from /top."
            actual = by_path[path]["pcf"]
            assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
            assert math.isclose(actual, wanted, rel_tol=1e-7, abs_tol=1e-9), \
                f"Incorrect PCF for {path}: expected {wanted}, got {actual}."

        # Validate ranking over every returned entry and independently validate the
        # expected ordering of the generated entries, including alphabetical ties.
        assert data == sorted(data, key=lambda item: (-item["pcf"], item["path"])), \
            "/top is not ordered by descending PCF with alphabetical path tie-breaking."
        generated_order = [item["path"] for item in data if item["path"] in expected]
        wanted_order = sorted(paths, key=lambda path: (-expected[path], path))
        assert generated_order == wanted_order
        assert generated_order.index(tie_a) < generated_order.index(tie_b), \
            "Equal-PCF files must be ordered alphabetically by path."

        # GET /top must inspect the ranking without removing entries.
        second = requests.get(f"{BASE_URL}/top?n=10000", timeout=10)
        assert second.status_code == 200
        assert second.json() == data, "GET /top removed or changed heap entries."
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
