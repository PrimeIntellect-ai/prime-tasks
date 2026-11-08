#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8000/profile"


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1F40" and fields[3] == "0A":
                inodes.add(fields[9])

    found = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    found.add(int(proc.name))
                    break
        except OSError:
            pass
    return found


def process_details(pid):
    base = Path("/proc") / str(pid)
    cmdline = [x.decode(errors="replace") for x in (base / "cmdline").read_bytes().split(b"\0") if x]
    cwd = Path(os.readlink(base / "cwd"))
    env = {}
    try:
        for item in (base / "environ").read_bytes().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="replace")] = value.decode(errors="replace")
    except OSError:
        pass
    return cmdline, cwd, env


def entry_file(cmdline, cwd, env):
    for arg in cmdline[1:]:
        candidate = Path(arg)
        if candidate.suffix == ".py":
            if not candidate.is_absolute():
                candidate = cwd / candidate
            if candidate.is_file():
                return candidate.resolve()

    module_spec = None
    for arg in cmdline[1:]:
        if ":" in arg and not arg.startswith("-"):
            module_spec = arg.split(":", 1)[0]
            break
    module_spec = module_spec or env.get("FLASK_APP", "").split(":", 1)[0]
    if module_spec:
        candidate = cwd / (module_spec.replace(".", "/") + ".py")
        if candidate.is_file():
            return candidate.resolve()
    return None


def reachable_sources(entry):
    roots = [Path("/app"), Path("/home/user"), entry.parent]
    seen = set()
    queue = [entry.resolve()]

    while queue:
        path = queue.pop()
        if path in seen or not path.is_file():
            continue
        seen.add(path)
        try:
            tree = ast.parse(path.read_text(errors="replace"), filename=str(path))
        except (OSError, SyntaxError):
            continue

        modules = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                modules.extend(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                modules.append(node.module)

        for module in modules:
            relative = Path(*module.split("."))
            for root in roots:
                for candidate in (root / relative.with_suffix(".py"), root / relative / "__init__.py"):
                    try:
                        resolved = candidate.resolve()
                    except OSError:
                        continue
                    if candidate.is_file() and resolved not in seen:
                        queue.append(resolved)
    return seen


def test_profile_endpoint_and_workflow_artifact():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Failed to connect to the server at {URL}. The server is not running or listening on the wrong port.")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {URL} timed out. The server is unresponsive.")
    except Exception as exc:
        pytest.fail(f"An unexpected error occurred while connecting to {URL}: {exc}")

    assert response.status_code == 200, f"Expected status code 200, but got {response.status_code}. Response text: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {URL} is not valid JSON. Response text: {response.text}")

    # Preserve the original result assertions.
    assert "thermal_limit" in data, "The JSON response is missing the 'thermal_limit' key."
    assert data["thermal_limit"] == 82, f"Expected 'thermal_limit' to be 82, but got {data['thermal_limit']}."
    assert "dominant_freq_hz" in data, "The JSON response is missing the 'dominant_freq_hz' key."
    assert data["dominant_freq_hz"] == 140, f"Expected 'dominant_freq_hz' to be 140, but got {data['dominant_freq_hz']}."
    assert "optimal_rpm" in data, "The JSON response is missing the 'optimal_rpm' key."
    assert data["optimal_rpm"] == 2500, f"Expected 'optimal_rpm' to be 2500, but got {data['optimal_rpm']}."

    # The response must come from an executable Python artifact, not a shell/netcat
    # process that merely emits the three known constants.
    pids = listener_pids()
    assert pids, "No process owns a listening socket on port 8000."

    entry = None
    details = []
    for pid in pids:
        try:
            cmdline, cwd, env = process_details(pid)
        except OSError:
            continue
        details.append(cmdline)
        if cmdline and ("python" in Path(cmdline[0]).name.lower() or "uvicorn" in Path(cmdline[0]).name.lower() or "flask" in Path(cmdline[0]).name.lower()):
            entry = entry_file(cmdline, cwd, env)
            if entry:
                break

    assert entry is not None, f"The listener is not backed by a discoverable Python source artifact. Listener commands: {details}"
    assert entry.is_file(), f"Server entry artifact does not exist: {entry}"

    sources = reachable_sources(entry)
    assert sources, "Could not read the server artifact or its locally imported workflow modules."
    combined = "\n".join(path.read_text(errors="replace") for path in sources)
    lowered = combined.lower()

    try:
        trees = [ast.parse(path.read_text(errors="replace"), filename=str(path)) for path in sources]
    except SyntaxError as exc:
        pytest.fail(f"The submitted Python workflow contains invalid syntax: {exc}")

    numbers = {
        node.value
        for tree in trees
        for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)) and not isinstance(node.value, bool)
    }

    assert "hpc_ambient.wav" in lowered, "The executed workflow does not read the required audio fixture."
    assert ("wavfile.read" in lowered or "readframes" in lowered), "The workflow does not decode the WAV audio into samples."
    assert (".fft" in lowered or ".rfft" in lowered or "scipy.fft" in lowered), "The workflow does not perform an FFT."
    assert ("multiprocessing" in lowered or "mpi4py" in lowered or "processpoolexecutor" in lowered), "The Monte Carlo workflow is not parallelized with multiprocessing or mpi4py."
    assert ("pool(" in lowered or ".map(" in lowered or ".starmap(" in lowered or "processpoolexecutor" in lowered or "comm." in lowered), "No multi-core distribution operation was found."
    assert "normal" in lowered, "The workflow does not generate normal-distributed temperature samples."
    assert 100000 in numbers, "The workflow does not request 100,000 Monte Carlo samples."
    assert {1000, 5000, 100}.issubset(numbers), "The required RPM range and 100-RPM step are not implemented."
    assert ("percentile" in lowered or "quantile" in lowered), "The workflow does not calculate the empirical 95th percentile."
    assert (95 in numbers or 0.95 in numbers), "The required 95th-percentile threshold is absent."
    assert ("wasserstein" in lowered or ("sort" in lowered and "abs" in lowered)), "The workflow does not calculate a 1D Wasserstein distance."

    # Reject a literal-only endpoint implementation. Values for the required
    # response fields must be expressions/names produced by the workflow.
    for tree in trees:
        for node in ast.walk(tree):
            if isinstance(node, ast.Dict):
                for key, value in zip(node.keys, node.values):
                    if isinstance(key, ast.Constant) and key.value in {"thermal_limit", "dominant_freq_hz", "optimal_rpm"}:
                        assert not isinstance(value, ast.Constant), f"Endpoint field {key.value!r} is returned as a fixed literal instead of a workflow result."
            if isinstance(node, ast.Call):
                for keyword in node.keywords:
                    if keyword.arg in {"thermal_limit", "dominant_freq_hz", "optimal_rpm"}:
                        assert not isinstance(keyword.value, ast.Constant), f"Endpoint field {keyword.arg!r} is returned as a fixed literal instead of a workflow result."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
