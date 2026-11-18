#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import signal
import stat
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

REQUESTS = []
REQUEST_LOCK = threading.Lock()
TEST_SERVER = None


def energy(graph):
    edges = graph.count("1")
    value = abs(edges - 5) * 1.5
    if graph[0] == "1" and graph[9] == "1":
        value -= 0.5
    if graph[1:4] == "000":
        value += 1.2
    return round(value + 1.0, 4)


class EnergyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length).decode("utf-8"))
            graph = data["graph"]
            if self.path != "/energy" or not isinstance(graph, str) or len(graph) != 10 or any(c not in "01" for c in graph):
                raise ValueError("invalid request")
            with REQUEST_LOCK:
                REQUESTS.append(graph)
            body = json.dumps({"energy": energy(graph)}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *args):
        pass


def _listener_inode(port):
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        return fields[9]
        except FileNotFoundError:
            pass
    return None


def _stop_port_listener(port):
    inode = _listener_inode(port)
    if not inode:
        return
    target = f"socket:[{inode}]"
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == target:
                        os.kill(int(name), signal.SIGTERM)
                        break
                except (FileNotFoundError, PermissionError, ProcessLookupError):
                    pass
        except (FileNotFoundError, PermissionError):
            pass
    deadline = time.time() + 5
    while _listener_inode(port) and time.time() < deadline:
        time.sleep(0.05)


def start_instrumented_api():
    global TEST_SERVER
    if TEST_SERVER is not None:
        return
    _stop_port_listener(8000)
    for _ in range(50):
        try:
            TEST_SERVER = ThreadingHTTPServer(("127.0.0.1", 8000), EnergyHandler)
            break
        except OSError:
            time.sleep(0.1)
    assert TEST_SERVER is not None, "Could not start instrumented energy API"
    threading.Thread(target=TEST_SERVER.serve_forever, daemon=True).start()


def test_flask_api_running():
    """Test that the Flask API is running on port 8000 and responds correctly."""
    url = "http://127.0.0.1:8000/energy"
    data = json.dumps({"graph": "0000000000"}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            res = json.loads(response.read().decode('utf-8'))
            assert "energy" in res, "API response missing 'energy' key."
            assert isinstance(res["energy"], (int, float)), "Energy value should be a number."
    except Exception as e:
        pytest.fail(f"Flask API is not running or failed to respond correctly: {e}")


def test_scripts_exist_and_executable():
    """Test that the required bash scripts exist and are executable."""
    scripts = [
        "/home/user/mcmc_sampler.sh",
        "/home/user/run_experiment.sh"
    ]
    for script in scripts:
        assert os.path.exists(script), f"Script missing: {script}"
        assert os.path.isfile(script), f"Not a file: {script}"
        assert os.access(script, os.X_OK), f"Script is not executable: {script}"


def test_sampler_executes_and_follows_mh(tmp_path):
    """Execute the sampler and validate API energies, proposals, and MH decisions."""
    start_instrumented_api()
    steps = 220
    output = tmp_path / "probe.log"
    with REQUEST_LOCK:
        REQUESTS.clear()

    result = subprocess.run(
        ["/home/user/mcmc_sampler.sh", "719", str(steps), str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, f"Sampler failed: {result.stderr}"
    assert output.is_file(), "Sampler did not create its requested output file"
    lines = [x.strip() for x in output.read_text().splitlines() if x.strip()]
    assert len(lines) == steps, f"Sampler produced {len(lines)} values instead of {steps}"
    values = [float(x) for x in lines]
    assert all(math.isfinite(x) for x in values), "Sampler output contains a non-finite value"

    with REQUEST_LOCK:
        requests = list(REQUESTS)

    # Accept both natural implementations: cache the initial energy and request one
    # proposal per step, or explicitly request current and proposed states each step.
    if len(requests) == steps + 1:
        assert requests[0] == "0000000000", "Chain did not start from the empty graph"
        pairs = [(None, requests[i + 1]) for i in range(steps)]
    elif len(requests) == 2 * steps:
        pairs = [(requests[2*i], requests[2*i + 1]) for i in range(steps)]
    elif len(requests) == 2 * steps + 1:
        assert requests[0] == "0000000000", "Initial energy was not evaluated for the empty graph"
        pairs = [(requests[1 + 2*i], requests[2 + 2*i]) for i in range(steps)]
    else:
        pytest.fail(f"Expected one current/proposal evaluation pattern per step, got {len(requests)} API requests")

    current = "0000000000"
    accepted_uphill = 0
    rejected_uphill = 0
    for i, ((queried_current, proposed), logged) in enumerate(zip(pairs, values), 1):
        if queried_current is not None:
            assert queried_current == current, f"Step {i} evaluated the wrong current state"
        assert sum(a != b for a, b in zip(current, proposed)) == 1, (
            f"Step {i} proposal does not flip exactly one of the 10 bits"
        )
        current_energy = energy(current)
        proposed_energy = energy(proposed)

        if proposed_energy <= current_energy:
            # Lower energies are mandatory accepts; equal energies have exp(0)=1.
            expected_state = proposed
            assert abs(logged - proposed_energy) < 1e-7, f"Step {i} failed to accept a mandatory proposal"
        else:
            if abs(logged - proposed_energy) < 1e-7:
                expected_state = proposed
                accepted_uphill += 1
            elif abs(logged - current_energy) < 1e-7:
                expected_state = current
                rejected_uphill += 1
            else:
                pytest.fail(f"Step {i} logged {logged}, which is neither current nor proposed API energy")
        current = expected_state

    assert accepted_uphill > 0, "No uphill proposal was ever accepted; MH probability appears unimplemented"
    assert rejected_uphill > 0, "No uphill proposal was ever rejected; MH probability appears unimplemented"


def test_run_experiment_executes_three_required_chains(tmp_path):
    """Run the experiment afresh and observe the three required sampler invocations."""
    start_instrumented_api()
    sampler = "/home/user/mcmc_sampler.sh"
    saved = tmp_path / "original_sampler.sh"
    invocation_log = tmp_path / "invocations.log"
    original = open(sampler, "rb").read()
    original_mode = stat.S_IMODE(os.stat(sampler).st_mode)
    saved.write_bytes(original)
    os.chmod(saved, original_mode)

    wrapper = f'''#!/bin/bash
printf '%s %s %s\\n' "$1" "$2" "$3" >> {invocation_log}
exec {saved} "$@"
'''
    for path in ["/home/user/chain_1.log", "/home/user/chain_2.log", "/home/user/chain_3.log", "/home/user/convergence_result.txt"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        with open(sampler, "w") as f:
            f.write(wrapper)
        os.chmod(sampler, 0o755)
        result = subprocess.run(
            ["/home/user/run_experiment.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"run_experiment.sh failed: {result.stderr}"
    finally:
        with open(sampler, "wb") as f:
            f.write(original)
        os.chmod(sampler, original_mode)

    calls = invocation_log.read_text().splitlines() if invocation_log.exists() else []
    expected = {
        "101 500 /home/user/chain_1.log",
        "202 500 /home/user/chain_2.log",
        "303 500 /home/user/chain_3.log",
    }
    assert len(calls) == 3 and set(calls) == expected, f"Incorrect sampler invocations: {calls}"


def test_log_files_exist_and_have_correct_length():
    """Test that the 3 chain log files exist, contain 500 lines each, and contain floats."""
    for i in range(1, 4):
        log_file = f"/home/user/chain_{i}.log"
        assert os.path.exists(log_file), f"Log file missing: {log_file}"

        with open(log_file, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]

        assert len(lines) == 500, f"{log_file} should contain exactly 500 lines, but has {len(lines)}."

        for idx, line in enumerate(lines):
            try:
                value = float(line)
                assert math.isfinite(value), f"Non-finite value in {log_file} at line {idx + 1}"
            except ValueError:
                pytest.fail(f"Invalid float value in {log_file} at line {idx + 1}: '{line}'")


def test_convergence_result():
    """Test that convergence_result.txt exists and contains the correct average of the last 100 steps."""
    result_file = "/home/user/convergence_result.txt"
    assert os.path.exists(result_file), f"Result file missing: {result_file}"

    with open(result_file, 'r') as f:
        content = f.read().strip()

    try:
        reported_avg = float(content)
    except ValueError:
        pytest.fail(f"convergence_result.txt does not contain a valid float: '{content}'")
    assert math.isfinite(reported_avg), "convergence_result.txt contains a non-finite value"

    last_100_values = []
    for i in range(1, 4):
        log_file = f"/home/user/chain_{i}.log"
        with open(log_file, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
            last_100_values.extend([float(x) for x in lines[-100:]])

    assert len(last_100_values) == 300, "Should have exactly 300 values for the final average calculation."
    expected_avg = sum(last_100_values) / 300.0

    assert abs(reported_avg - expected_avg) < 1e-3, (
        f"Reported average {reported_avg} in {result_file} does not match "
        f"the expected calculated average {expected_avg}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
